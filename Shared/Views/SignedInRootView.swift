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
/// Unified, platform-adaptive signed-in shell. One `TabView` plus
/// `.sidebarAdaptable` does the right thing on every supported platform.
private struct OperatorShell: View {
    let client: OperatorClient
    let eventStream: EventStream
    @State private var pending = PendingMessagesStore.shared

    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent") {
                dashboardTab
            }

            Tab("Stats", systemImage: "chart.bar.fill") {
                NavigationStack {
                    statsView.navigationTitle("Stats")
                }
            }

            #if !os(tvOS)
            Tab("Sessions", systemImage: "phone.connection.fill") {
                NavigationStack {
                    SessionListView(client: client).navigationTitle("Sessions")
                }
            }

            Tab("Messages", systemImage: "tray.full") {
                NavigationStack {
                    MessageListView(client: client).navigationTitle("Messages")
                }
            }
            .badge(pending.pendingCount)

            Tab("Events", systemImage: "antenna.radiowaves.left.and.right") {
                NavigationStack {
                    EventsFeedView(client: client, stream: eventStream).navigationTitle("Events")
                }
            }

            Tab("Questions", systemImage: "questionmark.bubble") {
                NavigationStack {
                    QuestionsView(client: client).navigationTitle("Questions")
                }
            }
            #endif

            Tab("System", systemImage: "cpu") {
                NavigationStack {
                    SystemView(client: client).navigationTitle("System")
                }
            }

            #if !os(macOS)
            Tab("Settings", systemImage: "gearshape") {
                SettingsView(isModal: false)
            }
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.Colors.accent)
        .liveActivityObserver()
        .task { pending.startPolling(using: client) }
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
