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
    var body: some View {
        TabView {
            NavigationStack {
                WatchStatusView()
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
                WatchLatestMessageView()
                    .navigationTitle("Latest")
            }
            .tabItem { Label("Latest", systemImage: "tray.full") }

            NavigationStack {
                WatchModerationView()
                    .navigationTitle("Moderation")
            }
            .tabItem { Label("Moderation", systemImage: "checkmark.shield") }
        }
        .tabViewStyle(.verticalPage)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

#endif
