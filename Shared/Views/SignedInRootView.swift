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
/// Declaration order is the shared navigation order.
enum OperatorTab: String, CaseIterable, Hashable {
    case dashboard, stats, sessions, messages, thermals, events, questions, instructions, audit, system, settings
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
            Tab("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent", value: .dashboard) {
                dashboardTab
                    .automaticRefreshEnabled(selection == .dashboard)
            }

            Tab("Stats", systemImage: "chart.bar.fill", value: .stats) {
                Group {
                    #if os(tvOS)
                    TVStatsView(client: client)
                    #else
                    NavigationStack {
                        statsView.navigationTitle("Stats")
                    }
                    #endif
                }
                .automaticRefreshEnabled(selection == .stats)
            }

            #if !os(tvOS)
            Tab("Sessions", systemImage: "phone.connection.fill", value: .sessions) {
                NavigationStack(path: $sessionPath) {
                    SessionListView(client: client).navigationTitle("Sessions")
                }
                .automaticRefreshEnabled(selection == .sessions)
            }

            Tab("Messages", systemImage: "tray.full", value: .messages) {
                NavigationStack(path: $messagePath) {
                    MessageListView(client: client).navigationTitle("Messages")
                }
                .automaticRefreshEnabled(selection == .messages)
            }
            .badge(pending.pendingCount)

            Tab("Thermals", systemImage: "thermometer.variable.and.figure", value: .thermals) {
                NavigationStack {
                    ThermalsView(client: client).navigationTitle("Thermals")
                }
                .automaticRefreshEnabled(selection == .thermals)
            }

            Tab("Events", systemImage: "antenna.radiowaves.left.and.right", value: .events) {
                NavigationStack {
                    EventsFeedView(client: client, stream: eventStream).navigationTitle("Events")
                }
                .automaticRefreshEnabled(selection == .events)
            }

            Tab("Questions", systemImage: "questionmark.bubble", value: .questions) {
                NavigationStack {
                    QuestionsView(client: client, isAdmin: currentUser.isAdmin)
                        .navigationTitle("Questions")
                }
                .automaticRefreshEnabled(selection == .questions)
            }

            if currentUser.isAdmin {
                Tab("Instructions", systemImage: "phone.badge.waveform", value: .instructions) {
                    NavigationStack {
                        InstructionsView(client: client).navigationTitle("Instructions")
                    }
                    .automaticRefreshEnabled(selection == .instructions)
                }

                // The trail is admin-only server-side; hiding the tab keeps a
                // non-admin from tapping into a guaranteed 403.
                Tab("Audit", systemImage: "list.bullet.rectangle.portrait", value: .audit) {
                    NavigationStack {
                        AuditLogView(client: client).navigationTitle("Audit")
                    }
                    .automaticRefreshEnabled(selection == .audit)
                }
            }
            #endif

            Tab("System", systemImage: "cpu", value: .system) {
                Group {
                    #if os(tvOS)
                    TVSystemView(client: client)
                    #else
                    NavigationStack {
                        SystemView(client: client).navigationTitle("System")
                    }
                    #endif
                }
                .automaticRefreshEnabled(selection == .system)
            }

            #if !os(macOS)
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView(isModal: false)
            }
            #endif
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
