//
//  SignedInRootView.swift
//  TelephoneBoothOperatorMobile
//
//  Signed-in shell with platform-appropriate dashboard and navigation.
//
import SwiftUI
#if os(iOS)
import UIKit
#endif

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
/// Unified, platform-adaptive signed-in shell. One `TabView` plus
/// `.sidebarAdaptable` does the right thing on every supported platform.
private struct OperatorShell: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @State private var compactMorePath: NavigationPath
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
        var initialMorePath = NavigationPath()
        if let requested, requested.isCompactMoreDestination {
            initialMorePath.append(requested)
        }
        _compactMorePath = State(initialValue: initialMorePath)
    }

    var body: some View {
        tabView
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.Colors.accent)
        .liveActivityObserver()
        .environment(currentUser)
        .task { pending.startPolling(using: client) }
        .task { currentUser.start() }
        .task { consumePendingNavigationTarget() }
        .task(id: usesCompactTabNavigation) {
            compactMorePath = NavigationPath()
            if usesCompactTabNavigation {
                if selection.isCompactMoreDestination {
                    compactMorePath.append(selection)
                }
            } else if selection == .more {
                selection = .dashboard
            }
        }
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
    private var tabView: some View {
        #if os(iOS)
        if usesCompactTabNavigation {
            compactTabView
        } else {
            adaptiveTabView
        }
        #else
        adaptiveTabView
        #endif
    }

    private var adaptiveTabView: some View {
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
    }

    #if os(iOS)
    private var compactTabView: some View {
        TabView(selection: compactTabSelection) {
            ForEach(OperatorTab.compactPrimaryNavigationOrder, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    tabContent(for: tab)
                }
                .badge(tab == .messages ? pending.pendingCount : 0)
            }
            Tab(OperatorTab.more.title, systemImage: OperatorTab.more.systemImage, value: .more) {
                compactMoreNavigation
            }
        }
    }

    private var compactTabSelection: Binding<OperatorTab> {
        Binding(
            get: {
                selection.isCompactPrimary ? selection : .more
            },
            set: { selected in
                selection = selected
                if selected != .more {
                    compactMorePath = NavigationPath()
                }
            }
        )
    }

    private var compactMoreNavigation: some View {
        NavigationStack(path: $compactMorePath) {
            List {
                ForEach(
                    OperatorTab.compactMoreNavigationOrder(isAdmin: currentUser.isAdmin),
                    id: \.self
                ) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .operatorListRowBackground()
                }
            }
            .operatorListStyle()
            .navigationTitle("More")
            .navigationDestination(for: OperatorTab.self) { tab in
                compactMoreDestination(for: tab)
                    .onAppear {
                        selection = tab
                    }
            }
        }
        .automaticRefreshEnabled(compactTabSelection.wrappedValue == .more)
        .onChange(of: compactMorePath.count) { _, count in
            if count == 0, !selection.isCompactPrimary {
                selection = .more
            }
        }
    }

    @ViewBuilder
    private func compactMoreDestination(for tab: OperatorTab) -> some View {
        switch tab {
        case .thermals:
            ThermalsView(client: client).navigationTitle("Thermals")
        case .events:
            EventsFeedView(client: client, stream: eventStream).navigationTitle("Events")
        case .questions:
            QuestionsView(client: client, isAdmin: currentUser.isAdmin)
                .navigationTitle("Questions")
        case .instructions where currentUser.isAdmin:
            InstructionsView(client: client).navigationTitle("Instructions")
        case .audit where currentUser.isAdmin:
            AuditLogView(client: client).navigationTitle("Audit")
        case .system:
            SystemView(client: client).navigationTitle("System")
        case .settings:
            SettingsView(isModal: false, embedsInNavigationStack: false)
        default:
            EmptyView()
        }
    }
    #endif

    private var usesCompactTabNavigation: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact
        #else
        false
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
        case .more:
            EmptyView()
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
        case .more:
            EmptyView()
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
        case .more:
            EmptyView()
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
            selectTab(.dashboard)
        case .stats:
            selectTab(.stats)
        case .sessions:
            selectTab(.sessions)
            sessionPath = []
        case .session(let id):
            selectTab(.sessions)
            sessionPath = [id]
        case .messages(let route):
            selectTab(.messages)
            switch route {
            case .list(let filter):
                messagePath = []
                messageFilter = filter
            case .detail(let id):
                messagePath = [id]
            }
            messageRouteRevision &+= 1
        case .thermals:
            selectTab(.thermals)
        case .system:
            selectTab(.system)
        }
    }

    private func selectTab(_ tab: OperatorTab) {
        selection = tab
        #if os(iOS)
        if usesCompactTabNavigation, tab.isCompactMoreDestination {
            compactMorePath = NavigationPath()
            compactMorePath.append(tab)
        } else if tab.isCompactPrimary {
            compactMorePath = NavigationPath()
        }
        #endif
    }
}
#endif

#Preview {
    SignedInRootView(client: .demo, eventStream: .demo)
}
