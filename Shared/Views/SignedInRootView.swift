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
private enum OperatorTab: String, Hashable {
    case dashboard, stats, sessions, messages, events, questions, audit, system, settings
}

/// Unified, platform-adaptive signed-in shell. One `TabView` plus
/// `.sidebarAdaptable` does the right thing on every supported platform.
private struct OperatorShell: View {
    let client: OperatorClient
    let eventStream: EventStream
    @State private var pending = PendingMessagesStore.shared
    @State private var currentUser: CurrentUserStore
    @State private var selection: OperatorTab
    @State private var messagePath: [String]
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
                #if os(tvOS)
                TVStatsView(client: client)
                #else
                NavigationStack {
                    statsView.navigationTitle("Stats")
                }
                #endif
                .automaticRefreshEnabled(selection == .stats)
            }

            #if !os(tvOS)
            Tab("Sessions", systemImage: "phone.connection.fill", value: .sessions) {
                NavigationStack {
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

            // The trail is admin-only server-side; hiding the tab keeps a
            // non-admin from tapping into a guaranteed 403.
            if currentUser.isAdmin {
                Tab("Audit", systemImage: "list.bullet.rectangle.portrait", value: .audit) {
                    NavigationStack {
                        AuditLogView(client: client).navigationTitle("Audit")
                    }
                    .automaticRefreshEnabled(selection == .audit)
                }
            }
            #endif

            Tab("System", systemImage: "cpu", value: .system) {
                #if os(tvOS)
                TVSystemView(client: client)
                #else
                NavigationStack {
                    SystemView(client: client).navigationTitle("System")
                }
                #endif
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
}
#endif

#Preview {
    SignedInRootView(client: .demo, eventStream: .demo)
}
