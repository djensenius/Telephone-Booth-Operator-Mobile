//
//  SignedInRootView.swift
//  TelephoneBoothOperatorMobile
//
//  Signed-in shell shown after a successful sign-in.
//
//  - watchOS keeps its bespoke vertical-paging dashboard.
//  - Every other platform shares a single `TabView` rendered with
//    `.tabViewStyle(.sidebarAdaptable)`, so each one gets its native
//    presentation automatically: a source-list sidebar on macOS, an
//    adaptive sidebar/tab bar on iPadOS, a bottom bar on iPhone, a top bar
//    on tvOS, and an ornament on visionOS.
//  - Settings is a tab everywhere except macOS, where it lives in the
//    standard app menu (⌘, → `MacSettingsView`).
//  - tvOS only surfaces the read-only screens that exist on that platform
//    (Dashboard booth wall, Stats, System) plus Settings.
//

import SwiftUI

public struct SignedInRootView: View {
    private let client: OperatorClient
    private let eventStream: EventStream

    public init(
        client: OperatorClient = .shared,
        eventStream: EventStream = .shared
    ) {
        self.client = client
        self.eventStream = eventStream
    }

    public var body: some View {
        #if os(watchOS)
        WatchHomeView(client: client)
            .liveActivityObserver()
        #else
        OperatorShell(client: client, eventStream: eventStream)
        #endif
    }
}

#if !os(watchOS)
/// Stable identifiers for the signed-in tabs, used to drive selection and to
/// let screenshot automation open a specific tab via `-uiScreenshotTab`.
enum OperatorTab: String, Hashable {
    case dashboard, stats, sessions, messages, thermals, events, questions, instructions, audit, system, settings

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .stats: return "Stats"
        case .sessions: return "Sessions"
        case .messages: return "Messages"
        case .thermals: return "Thermals"
        case .events: return "Events"
        case .questions: return "Questions"
        case .instructions: return "Instructions"
        case .audit: return "Audit"
        case .system: return "System"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
        case .stats: return "chart.bar.fill"
        case .sessions: return "phone.connection.fill"
        case .messages: return "tray.full"
        case .thermals: return "thermometer.variable.and.figure"
        case .events: return "antenna.radiowaves.left.and.right"
        case .questions: return "questionmark.bubble"
        case .instructions: return "phone.badge.waveform"
        case .audit: return "list.bullet.rectangle.portrait"
        case .system: return "cpu"
        case .settings: return "gearshape"
        }
    }

    static func sharedNavigationOrder(
        isAdmin: Bool,
        includesSettings: Bool
    ) -> [OperatorTab] {
        var tabs: [OperatorTab] = [
            .dashboard,
            .stats,
            .sessions,
            .messages,
            .thermals,
            .events,
            .questions
        ]
        if isAdmin {
            tabs.append(contentsOf: [.instructions, .audit])
        }
        tabs.append(.system)
        if includesSettings {
            tabs.append(.settings)
        }
        return tabs
    }

    static let televisionNavigationOrder: [OperatorTab] = [
        .dashboard,
        .stats,
        .system,
        .settings
    ]
}

/// Unified, platform-adaptive signed-in shell. One `TabView` plus
/// `.sidebarAdaptable` does the right thing on every supported platform.
private struct OperatorShell: View {
    let client: OperatorClient
    let eventStream: EventStream
    @State private var pending = PendingMessagesStore.shared
    @State private var notifications = NotificationManager.shared
    @State private var currentUser: CurrentUserStore
    @State private var selection: OperatorTab
    @State private var messagePath: [String]
    @State private var sessionPath: [String] = []
    #if os(tvOS)
    @State private var config = AppConfig.shared
    #endif

    init(client: OperatorClient, eventStream: EventStream) {
        self.client = client
        self.eventStream = eventStream
        _currentUser = State(initialValue: CurrentUserStore(client: client))
        let requested = LaunchEnv.screenshotMessageId == nil
            ? LaunchEnv.screenshotTab.flatMap(OperatorTab.init(rawValue:))
            : .messages
        _selection = State(initialValue: requested ?? .dashboard)
        _messagePath = State(initialValue: LaunchEnv.screenshotMessageId.map { [$0] } ?? [])
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(visibleTabs, id: \.self) { tab in
                #if os(tvOS)
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    tabContent(for: tab)
                }
                #else
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    tabContent(for: tab)
                }
                .badge(tab == .messages ? pending.pendingCount : 0)
                #endif
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.Colors.accent)
        .liveActivityObserver()
        .environment(currentUser)
        .task { pending.startPolling(using: client) }
        .task { currentUser.start() }
        .task { handleNotificationTarget() }
        .onChange(of: notifications.navigationTarget) {
            handleNotificationTarget()
        }
        #if !os(tvOS) && canImport(Speech) && canImport(FoundationModels)
        .automaticMessageProcessing(client: client)
        #endif
        #if os(tvOS)
        .tvScreensaver(
            enabled: config.tvScreensaverEnabled,
            idleSeconds: config.tvScreensaverIdleSeconds,
            client: client
        )
        #endif
    }

    @ViewBuilder
    private func tabContent(for tab: OperatorTab) -> some View {
        #if os(tvOS)
        televisionTabContent(for: tab)
        #else
        switch tab {
        case .dashboard, .stats, .system, .settings:
            shellTabContent(for: tab)
        default:
            workflowTabContent(for: tab)
        }
        #endif
    }

    #if os(tvOS)
    @ViewBuilder
    private func televisionTabContent(for tab: OperatorTab) -> some View {
        switch tab {
        case .dashboard:
            dashboardTab
                .automaticRefreshEnabled(selection == .dashboard)
        case .stats:
            TVStatsView(client: client)
                .automaticRefreshEnabled(selection == .stats)
        case .system:
            TVSystemView(client: client)
                .automaticRefreshEnabled(selection == .system)
        case .settings:
            SettingsView(isModal: false)
        default:
            EmptyView()
        }
    }
    #else
    @ViewBuilder
    private func shellTabContent(for tab: OperatorTab) -> some View {
        switch tab {
        case .dashboard:
            dashboardTab
                .automaticRefreshEnabled(selection == .dashboard)
        case .stats:
            NavigationStack {
                statsView.navigationTitle("Stats")
            }
            .automaticRefreshEnabled(selection == .stats)
        case .system:
            NavigationStack {
                SystemView(client: client).navigationTitle("System")
            }
            .automaticRefreshEnabled(selection == .system)
        case .settings:
            #if os(macOS)
            EmptyView()
            #else
            SettingsView(isModal: false)
            #endif
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func workflowTabContent(for tab: OperatorTab) -> some View {
        switch tab {
        case .sessions:
            NavigationStack(path: $sessionPath) {
                SessionListView(client: client).navigationTitle("Sessions")
            }
            .automaticRefreshEnabled(selection == .sessions)
        case .messages:
            NavigationStack(path: $messagePath) {
                MessageListView(client: client).navigationTitle("Messages")
            }
            .automaticRefreshEnabled(selection == .messages)
        case .thermals:
            NavigationStack {
                ThermalsView(client: client).navigationTitle("Thermals")
            }
            .automaticRefreshEnabled(selection == .thermals)
        case .events:
            NavigationStack {
                EventsFeedView(client: client, stream: eventStream).navigationTitle("Events")
            }
            .automaticRefreshEnabled(selection == .events)
        case .questions:
            NavigationStack {
                QuestionsView(client: client, isAdmin: currentUser.isAdmin)
                    .navigationTitle("Questions")
            }
            .automaticRefreshEnabled(selection == .questions)
        case .instructions:
            NavigationStack {
                InstructionsView(client: client).navigationTitle("Instructions")
            }
            .automaticRefreshEnabled(selection == .instructions)
        case .audit:
            NavigationStack {
                AuditLogView(client: client).navigationTitle("Audit")
            }
            .automaticRefreshEnabled(selection == .audit)
        default:
            EmptyView()
        }
    }
    #endif

    private var visibleTabs: [OperatorTab] {
        #if os(tvOS)
        return OperatorTab.televisionNavigationOrder
        #elseif os(macOS)
        return OperatorTab.sharedNavigationOrder(
            isAdmin: currentUser.isAdmin,
            includesSettings: false
        )
        #else
        return OperatorTab.sharedNavigationOrder(
            isAdmin: currentUser.isAdmin,
            includesSettings: true
        )
        #endif
    }

    @ViewBuilder
    private var dashboardTab: some View {
        #if os(tvOS)
        TVBoothWallView(client: client)
        #else
        NavigationStack {
            StatusDashboardView(client: client).navigationTitle("Dashboard")
        }
        #endif
    }

    @ViewBuilder
    private var statsView: some View {
        #if os(macOS)
        MacStatsView(client: client)
        #else
        StatsView(client: client)
        #endif
    }

    private func handleNotificationTarget() {
        guard let target = notifications.navigationTarget else { return }
        switch target {
        case .messages(let messageId):
            selection = .messages
            messagePath = messageId.map { [$0] } ?? []
        case .session(let id):
            selection = .sessions
            sessionPath = [id]
        }
        notifications.clearNavigationTarget()
    }
}
#endif

#if !os(watchOS) && !os(tvOS) && canImport(Speech) && canImport(FoundationModels)
private extension View {
    @ViewBuilder
    func automaticMessageProcessing(client: OperatorClient) -> some View {
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            modifier(AutomaticMessageProcessingModifier(client: client))
        } else {
            self
        }
    }
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
private struct AutomaticMessageProcessingModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: AutomaticMessageProcessingCoordinator

    init(client: OperatorClient) {
        _coordinator = State(initialValue: AutomaticMessageProcessingCoordinator(client: client))
    }

    func body(content: Content) -> some View {
        placedStatus(content)
            .task {
                coordinator.setActive(scenePhase == .active)
            }
            .onChange(of: scenePhase) {
                coordinator.setActive(scenePhase == .active)
            }
            .onDisappear {
                coordinator.setActive(false)
            }
    }

    @ViewBuilder
    private func placedStatus(_ content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: coordinator.shouldPresentStatus) {
                MessageProcessingQueueStatus(coordinator: coordinator)
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.vertical, Theme.Spacing.small)
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if coordinator.shouldPresentStatus {
                    MessageProcessingQueueStatus(coordinator: coordinator)
                        .padding(.horizontal, Theme.Spacing.medium)
                        .padding(.vertical, Theme.Spacing.small)
                        .frame(maxWidth: 520)
                        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cornerRadius))
                        .padding(.horizontal, Theme.Spacing.medium)
                        .padding(.bottom, Theme.Spacing.small)
                }
            }
        }
        #else
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if coordinator.shouldPresentStatus {
                MessageProcessingQueueStatus(coordinator: coordinator)
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.vertical, Theme.Spacing.small)
                    .frame(maxWidth: 520)
                    .glassCardBackground()
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.bottom, Theme.Spacing.small)
            }
        }
        #endif
    }
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
private struct MessageProcessingQueueStatus: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement
    let coordinator: AutomaticMessageProcessingCoordinator

    var body: some View {
        let summary = coordinator.summary
        statusContent(summary)
    }

    private func statusContent(_ summary: MessageProcessingSummary?) -> some View {
        HStack(spacing: Theme.Spacing.small) {
            statusIndicator
            if accessoryPlacement == .inline {
                Text(compactStatusText(summary))
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(
                        coordinator.canRetry ? Theme.Colors.error : Theme.Colors.textPrimary
                    )
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Messages · \(scopeText(summary))")
                        .font(Theme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(coordinator.status.text)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(
                            coordinator.canRetry ? Theme.Colors.error : Theme.Colors.textSecondary
                        )
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if coordinator.canRetry {
                retryButton(compact: accessoryPlacement == .inline)
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if coordinator.isProcessing {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: coordinator.canRetry
                ? "exclamationmark.triangle.fill"
                : "tray.and.arrow.down.fill")
            .foregroundStyle(coordinator.canRetry ? Theme.Colors.error : Theme.Colors.accent)
        }
    }

    private func retryButton(compact: Bool) -> some View {
        Button {
            coordinator.retry()
        } label: {
            if compact {
                Image(systemName: "arrow.clockwise")
                    .accessibilityLabel("Retry message processing")
            } else {
                Label("Retry", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Colors.accent)
        .font(Theme.Fonts.caption.weight(.semibold))
        .frame(minWidth: 44, minHeight: 44)
    }

    private func compactStatusText(_ summary: MessageProcessingSummary?) -> String {
        if coordinator.canRetry { return "Processing failed" }
        if coordinator.isProcessing { return coordinator.status.text }
        return scopeText(summary)
    }

    private func scopeText(_ summary: MessageProcessingSummary?) -> String {
        guard let summary else { return "checking queue" }
        let remaining = summary.queued + summary.leased
        return "\(remaining) remaining"
    }
}
#endif

#Preview {
    SignedInRootView(client: .demo, eventStream: .demo)
}
