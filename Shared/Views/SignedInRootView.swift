//
//  SignedInRootView.swift
//  TelephoneBoothOperatorMobile
//
//  Signed-in shell with platform-appropriate dashboard and navigation.
//
import SwiftUI

public struct SignedInRootView: View {
    private let client: OperatorClient
    private let eventStream: EventStream
    private let navigationStore: AppNavigationStore

    public init(
        client: OperatorClient = .shared,
        eventStream: EventStream = .shared,
        navigationStore: AppNavigationStore = .shared
    ) {
        self.client = client
        self.eventStream = eventStream
        self.navigationStore = navigationStore
    }

    public var body: some View {
        #if os(watchOS)
        WatchHomeView(client: client)
            .liveActivityObserver()
        #else
        OperatorShell(
            client: client,
            eventStream: eventStream,
            navigationStore: navigationStore
        )
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

    static func televisionNavigationOrder(isAdmin: Bool) -> [OperatorTab] {
        var tabs: [OperatorTab] = [
            .dashboard, .stats, .sessions, .thermals, .events
        ]
        if isAdmin { tabs.append(.audit) }
        return tabs + [.system, .settings]
    }
}

/// Unified, platform-adaptive signed-in shell. One `TabView` plus
/// `.sidebarAdaptable` does the right thing on every supported platform.
private struct OperatorShell: View {
    let client: OperatorClient
    let eventStream: EventStream
    let navigationStore: AppNavigationStore
    @State private var pending = PendingMessagesStore.shared
    @State private var currentUser: CurrentUserStore
    @State private var selection: OperatorTab
    @State private var messagePath: [String]
    @State private var messageFilter: MessageListFilter = .all
    @State private var messageRouteRevision: UInt = 0
    @State private var sessionPath: [String] = []
    #if os(tvOS)
    @State private var config = AppConfig.shared
    #endif

    init(
        client: OperatorClient,
        eventStream: EventStream,
        navigationStore: AppNavigationStore
    ) {
        self.client = client
        self.eventStream = eventStream
        self.navigationStore = navigationStore
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
        .task { consumePendingNavigationTarget() }
        .onChange(of: navigationStore.routeGeneration) {
            consumePendingNavigationTarget()
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
        case .sessions:
            NavigationStack(path: $sessionPath) {
                TVSessionsView(client: client)
                    .navigationDestination(for: String.self) { sessionId in
                        TVSessionDetailView(sessionId: sessionId, client: client)
                    }
            }
            .automaticRefreshEnabled(selection == .sessions)
        case .thermals:
            TVThermalsView(client: client).automaticRefreshEnabled(selection == .thermals)
        case .events:
            TVEventsView(client: client, stream: eventStream)
                .automaticRefreshEnabled(selection == .events)
        case .audit:
            TVAuditView(client: client).automaticRefreshEnabled(selection == .audit)
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
                MessageListView(
                    client: client,
                    routeFilter: messageFilter,
                    routeRevision: messageRouteRevision
                )
                .navigationTitle("Messages")
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
        return OperatorTab.televisionNavigationOrder(isAdmin: currentUser.isAdmin)
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
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
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

    private func consumePendingNavigationTarget() {
        guard let target = navigationStore.consumePendingTarget() else { return }
        switch target {
        case .dashboard:
            selection = .dashboard
        case .stats:
            selection = .stats
        case .sessions:
            selection = .sessions
            sessionPath = []
        case .session(let id):
            selection = .sessions
            sessionPath = [id]
        case .messages(let route):
            selection = .messages
            switch route {
            case .list(let filter):
                messagePath = []
                messageFilter = filter
            case .detail(let id):
                messagePath = [id]
            }
            messageRouteRevision &+= 1
        case .thermals:
            selection = .thermals
        case .system:
            selection = .system
        }
    }
}
#endif

#Preview {
    SignedInRootView(client: .demo, eventStream: .demo)
}
