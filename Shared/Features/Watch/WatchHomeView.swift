//
//  WatchHomeView.swift
//  TelephoneBoothOperatorMobile
//
//  Top-level watch UI: four vertically paged screens.
//  Settings live
//  behind a toolbar gear on the Status page.
//

#if os(watchOS)

import SwiftUI

extension MessageStatus {
    var watchStatusColor: Color {
        switch self {
        case .approved: return Theme.Colors.success
        case .rejected: return Theme.Colors.error
        case .pending, .received: return Theme.Colors.warning
        case .uploading: return .secondary
        case .unknown: return .secondary
        }
    }
}

struct WatchMessageHeader: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(message.status.watchStatusColor)
                    .frame(width: 8, height: 8)
                Text(message.status.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(message.status.watchStatusColor)
            }
            Text(message.receivedAt ?? message.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

struct WatchHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    @State private var selection = WatchPage.status
    @State private var path: [WatchModerationDestination] = []
    @State private var routeNotice: String?
    @State private var refreshRevision = 0
    @State private var latestModel = WatchMessageListModel()
    @State private var moderationModel = WatchMessageListModel()
    let client: OperatorClient
    let navigationStore: AppNavigationStore

    init(client: OperatorClient = .shared, navigationStore: AppNavigationStore = .shared) {
        self.client = client
        self.navigationStore = navigationStore
        let initialPage = LaunchEnv.screenshotTab.flatMap(WatchPage.init(rawValue:)) ?? .status
        _selection = State(initialValue: initialPage)
        _path = State(initialValue: LaunchEnv.screenshotMessageId.map { [.message($0)] } ?? [])
    }

    private func refreshEnabled(on page: WatchPage) -> Bool {
        scenePhase == .active && selection == page && path.isEmpty && !showingSettings
    }

    var body: some View {
        // A single NavigationStack wraps the vertical-paging TabView. Giving
        // each page its own NavigationStack crashes watchOS with a nested
        // "wrapped navigation controllers" exception, so the title is driven
        // by the current selection instead.
        NavigationStack(path: $path) {
            TabView(selection: $selection) {
                WatchStatusView(client: client)
                    .automaticRefreshEnabled(refreshEnabled(on: .status))
                    .tabItem { Label("Status", systemImage: "gauge.with.dots.needle.bottom.50percent") }
                    .tag(WatchPage.status)

                WatchLatestMessageView(client: client, refreshRevision: refreshRevision, model: latestModel)
                    .automaticRefreshEnabled(refreshEnabled(on: .latest))
                    .tabItem { Label("Latest", systemImage: "tray.full") }
                    .tag(WatchPage.latest)

                WatchModerationView(client: client, refreshRevision: refreshRevision, model: moderationModel)
                    .automaticRefreshEnabled(refreshEnabled(on: .moderation))
                    .tabItem { Label("Moderation", systemImage: "checkmark.shield") }
                    .tag(WatchPage.moderation)

                WatchStatsView(client: client)
                    .automaticRefreshEnabled(refreshEnabled(on: .stats))
                    .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                    .tag(WatchPage.stats)
            }
            .tabViewStyle(.verticalPage)
            .navigationTitle(selection.title)
            .navigationDestination(for: WatchModerationDestination.self) { destination in
                switch destination {
                case .message(let id):
                    WatchModerationDetailView(messageId: id, client: client) { updated in
                        latestModel.applyDecision(updated, filter: .all)
                        moderationModel.applyDecision(updated, filter: .review)
                        refreshRevision += 1
                    }
                    .automaticRefreshEnabled(scenePhase == .active && !showingSettings)
                }
            }
            .toolbar {
                if selection == .status {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear { consumeNavigation() }
        .onChange(of: navigationStore.routeGeneration) { _, _ in consumeNavigation() }
        .alert("Open on iPhone", isPresented: Binding(
            get: { routeNotice != nil },
            set: { if !$0 { routeNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(routeNotice ?? "")
        }
    }

    private func consumeNavigation() {
        guard let target = navigationStore.consumePendingTarget() else { return }
        let route = WatchRoute(target: target)
        showingSettings = false
        selection = route.page
        path = route.path
        routeNotice = route.notice
    }
}

enum WatchPage: String, Hashable {
    case status, latest, moderation, stats

    var title: String {
        switch self {
        case .status: return "Status"
        case .latest: return "Latest"
        case .moderation: return "Moderation"
        case .stats: return "Stats"
        }
    }
}

struct WatchRoute: Equatable {
    var page: WatchPage = .status
    var path: [WatchModerationDestination] = []
    var notice: String?

    init(target: AppNavigationTarget) {
        switch target {
        case .dashboard:
            break
        case .stats:
            page = .stats
        case .messages(.detail(let id)):
            page = .moderation
            path = [.message(id)]
        case .messages(.list(let filter)):
            if filter == .review {
                page = .moderation
            } else {
                page = .latest
                notice = "The full message list and filters are available on iPhone. Watch shows the latest message."
            }
        case .sessions, .session, .thermals, .system:
            notice = "This screen is available on iPhone. Watch shows a compact booth status summary."
        }
    }
}

private struct WatchNotificationScopeID: Equatable {
    let scope: DeliveredNotificationScope?
    let enabled: Bool
}

private struct WatchMessageNotifications: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.automaticRefreshEnabled) private var automaticRefreshEnabled
    let scope: DeliveredNotificationScope?

    func body(content: Content) -> some View {
        let enabled = scenePhase == .active && automaticRefreshEnabled
        content
            .notificationVisibilityScope(scope)
            .task(id: WatchNotificationScopeID(scope: scope, enabled: enabled)) {
                guard enabled, let scope else { return }
                await NotificationManager.shared.clearDeliveredNotifications(in: scope)
            }
    }
}

extension View {
    func watchMessageNotifications(_ scope: DeliveredNotificationScope?) -> some View {
        modifier(WatchMessageNotifications(scope: scope))
    }
}

#endif
