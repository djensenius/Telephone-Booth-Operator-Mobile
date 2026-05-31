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
        #elseif os(tvOS)
        compactShell
        #elseif os(macOS)
        MacSidebarShell(client: client, eventStream: eventStream)
        #else
        tabbedShell
            .liveActivityObserver()
        #endif
    }

    #if !os(watchOS) && !os(tvOS) && !os(macOS)
    private var tabbedShell: some View {
        TabView {
            NavigationStack {
                StatusDashboardView(client: client)
                    .navigationTitle("Operator")
                    .toolbar { settingsToolbar }
            }
            .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent") }

            NavigationStack {
                StatsView(client: client)
                    .navigationTitle("Stats")
                    .toolbar { settingsToolbar }
            }
            .tabItem { Label("Stats", systemImage: "chart.bar.fill") }

            NavigationStack {
                SessionListView(client: client)
                    .navigationTitle("Sessions")
                    .toolbar { settingsToolbar }
            }
            .tabItem { Label("Sessions", systemImage: "phone.connection.fill") }

            NavigationStack {
                MessageListView(client: client)
                    .navigationTitle("Messages")
                    .toolbar { settingsToolbar }
            }
            .tabItem { Label("Messages", systemImage: "tray.full") }

            NavigationStack {
                EventsFeedView(client: client, stream: eventStream)
                    .navigationTitle("Events")
                    .toolbar { settingsToolbar }
            }
            .tabItem { Label("Events", systemImage: "antenna.radiowaves.left.and.right") }

            NavigationStack {
                QuestionsView(client: client)
                    .navigationTitle("Questions")
                    .toolbar { settingsToolbar }
            }
            .tabItem { Label("Questions", systemImage: "questionmark.bubble") }

            NavigationStack {
                SystemView(client: client)
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

    #if os(tvOS)
    private var compactShell: some View {
        TVBoothWallView(client: client)
    }
    #endif
}

#if os(macOS)
/// The sections shown in the macOS sidebar. Mirrors the iOS tab set.
private enum OperatorSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, stats, sessions, messages, events, questions, system, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .stats:     return "Stats"
        case .sessions:  return "Sessions"
        case .messages:  return "Messages"
        case .events:    return "Events"
        case .questions: return "Questions"
        case .system:    return "System"
        case .settings:  return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
        case .stats:     return "chart.bar.fill"
        case .sessions:  return "phone.connection.fill"
        case .messages:  return "tray.full"
        case .events:    return "antenna.radiowaves.left.and.right"
        case .questions: return "questionmark.bubble"
        case .system:    return "cpu"
        case .settings:  return "gearshape"
        }
    }
}

/// Native macOS shell: a source-list sidebar paired with a detail column.
/// Settings live in the standard app menu (⌘,) rather than a toolbar sheet.
private struct MacSidebarShell: View {
    @State private var selection: OperatorSection? = .dashboard
    let client: OperatorClient
    let eventStream: EventStream

    var body: some View {
        NavigationSplitView {
            List(OperatorSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
            .navigationTitle("Operator")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            NavigationStack {
                detail(for: selection ?? .dashboard)
            }
            .id(selection)
        }
    }

    @ViewBuilder
    private func detail(for section: OperatorSection) -> some View {
        switch section {
        case .dashboard:
            StatusDashboardView(client: client).navigationTitle(section.title)
        case .stats:
            StatsView(client: client).navigationTitle(section.title)
        case .sessions:
            SessionListView(client: client).navigationTitle(section.title)
        case .messages:
            MessageListView(client: client).navigationTitle(section.title)
        case .events:
            EventsFeedView(client: client, stream: eventStream).navigationTitle(section.title)
        case .questions:
            QuestionsView(client: client).navigationTitle(section.title)
        case .system:
            SystemView(client: client).navigationTitle(section.title)
        case .settings:
            SettingsView().navigationTitle(section.title)
        }
    }
}
#endif

#Preview {
    SignedInRootView(client: .demo, eventStream: .demo)
}
