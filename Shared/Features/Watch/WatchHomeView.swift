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
    let client: OperatorClient

    init(client: OperatorClient = .shared) {
        self.client = client
    }

    var body: some View {
        TabView {
            NavigationStack {
                WatchStatusView(client: client)
                    .navigationTitle("Status")
                    .toolbar {
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
            .tabItem { Label("Status", systemImage: "gauge.with.dots.needle.bottom.50percent") }

            NavigationStack {
                WatchLatestMessageView(client: client)
                    .navigationTitle("Latest")
            }
            .tabItem { Label("Latest", systemImage: "tray.full") }

            NavigationStack {
                WatchModerationView(client: client)
                    .navigationTitle("Moderation")
            }
            .tabItem { Label("Moderation", systemImage: "checkmark.shield") }

            NavigationStack {
                WatchStatsView(client: client)
                    .navigationTitle("Stats")
            }
            .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
        }
        .tabViewStyle(.verticalPage)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

#endif
