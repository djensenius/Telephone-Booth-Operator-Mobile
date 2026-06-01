//
//  WatchHomeView.swift
//  TelephoneBoothOperatorMobile
//
//  Top-level watch UI: a vertical-paging TabView with three tabs
//  — Status, Latest message, Moderation queue. Settings live
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

struct WatchHomeView: View {
    @State private var showingSettings = false
    @State private var selection = WatchPage.status
    let client: OperatorClient

    init(client: OperatorClient = .shared) {
        self.client = client
    }

    private enum WatchPage: Hashable {
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

    var body: some View {
        // A single NavigationStack wraps the vertical-paging TabView. Giving
        // each page its own NavigationStack crashes watchOS with a nested
        // "wrapped navigation controllers" exception, so the title is driven
        // by the current selection instead.
        NavigationStack {
            TabView(selection: $selection) {
                WatchStatusView(client: client)
                    .tabItem { Label("Status", systemImage: "gauge.with.dots.needle.bottom.50percent") }
                    .tag(WatchPage.status)

                WatchLatestMessageView(client: client)
                    .tabItem { Label("Latest", systemImage: "tray.full") }
                    .tag(WatchPage.latest)

                WatchModerationView(client: client)
                    .tabItem { Label("Moderation", systemImage: "checkmark.shield") }
                    .tag(WatchPage.moderation)

                WatchStatsView(client: client)
                    .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                    .tag(WatchPage.stats)
            }
            .tabViewStyle(.verticalPage)
            .navigationTitle(selection.title)
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
    }
}

#endif
