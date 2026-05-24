//
//  SignedInRootView.swift
//  TelephoneBoothOperatorMobile
//
//  Tab-based shell shown after a successful sign-in.
//
//  - iOS / iPadOS / macOS / visionOS get a three-tab interface:
//    Dashboard, Sessions, System (plus a Settings toolbar action).
//  - watchOS keeps a single scrollable dashboard.
//  - tvOS is intentionally minimal (read-only dashboard) until PR 8
//    expands it.
//

import SwiftUI

public struct SignedInRootView: View {
    @State private var showingSettings = false

    public init() {}

    public var body: some View {
        #if os(watchOS) || os(tvOS)
        compactShell
        #else
        tabbedShell
        #endif
    }

    #if !os(watchOS) && !os(tvOS)
    private var tabbedShell: some View {
        TabView {
            NavigationStack {
                StatusDashboardView()
                    .navigationTitle("Operator")
                    .toolbar { settingsToolbar }
            }
            .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent") }

            NavigationStack {
                SessionListView()
                    .navigationTitle("Sessions")
                    .toolbar { settingsToolbar }
            }
            .tabItem { Label("Sessions", systemImage: "phone.connection.fill") }

            NavigationStack {
                SystemView()
                    .navigationTitle("System")
                    .toolbar { settingsToolbar }
            }
            .tabItem { Label("System", systemImage: "cpu") }
        }
        .tint(Theme.Colors.accent)
        .sheet(isPresented: $showingSettings) {
            #if os(macOS)
            SettingsView()
                .frame(minWidth: 420, minHeight: 360)
            #else
            SettingsView()
            #endif
        }
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
            }
            .accessibilityLabel("Settings")
        }
    }
    #endif

    #if os(watchOS) || os(tvOS)
    private var compactShell: some View {
        NavigationStack {
            StatusDashboardView()
                .navigationTitle("Operator")
                #if os(watchOS)
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
                #endif
        }
        #if os(watchOS)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        #endif
    }
    #endif
}

#Preview {
    SignedInRootView()
}
