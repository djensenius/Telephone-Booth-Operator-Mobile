//
//  StatusDashboardView.swift
//  TelephoneBoothOperatorMobile
//
//  Live booth status panel and recent uptime chart. The chart pulls
//  `/v1/status/history` and renders it with Swift Charts. State, queue
//  counts, and operator profile come from `/v1/stats/summary` and
//  `/v1/auth/me`.
//

import SwiftUI
#if canImport(Charts)
import Charts
#endif

public struct StatusDashboardView: View {
    @State private var auth = AuthManager.shared
    @State private var config = AppConfig.shared
    @State private var profile: OperatorMe?
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var liveStore: BoothStatusLiveStore

    private let client: OperatorClient

    public init(client: OperatorClient = .shared, liveStore: BoothStatusLiveStore? = nil) {
        self.client = client
        _liveStore = State(initialValue: liveStore ?? (client.demoMode ? .demo : .shared))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                if let displayError {
                    BannerView(message: displayError, kind: .error)
                }
                statsCard
                SystemVitalsStrip(
                    snapshot: liveStore.systemEnvelope?.snapshot,
                    receivedAt: liveStore.systemEnvelope?.receivedAt
                )
                #if !os(watchOS) && !os(tvOS)
                if canShowChart {
                    historyChartCard
                }
                #endif
            }
            .padding(Theme.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.background)
        #if !os(watchOS) && !os(tvOS)
        .toolbar { accountToolbar }
        #endif
        .refreshableIfAvailable {
            await refresh()
        }
        .task {
            await refresh()
        }
        .boothStatusLive(liveStore)
    }

    public func refresh() async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        async let meResult = capture { try await client.fetchMe() }
        async let storeRefresh: Void = liveStore.refreshNow()
        let meOutcome = await meResult
        await storeRefresh
        if let newMe = try? meOutcome.get() {
            profile = newMe
        } else if profile == nil {
            let reason = describe(error: meOutcome.failureOrNil)
            errorMessage = "Couldn't reach the operator: \(reason)"
        }
    }

    private func capture<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func describe(error: Error?) -> String {
        guard let error else { return "unknown error" }
        switch error {
        case OperatorError.unauthorized(let body):
            return "401 unauthorized (\(body.prefix(120)))"
        case OperatorError.httpError(let status, let body):
            return "HTTP \(status) (\(body.prefix(120)))"
        case OperatorError.transport(let inner):
            return "transport — \(inner.localizedDescription)"
        case OperatorError.unauthenticated:
            return "not signed in"
        default:
            return error.localizedDescription
        }
    }

    private var displayError: String? {
        errorMessage ?? liveStore.lastError
    }

    #if !os(watchOS) && !os(tvOS)
    /// Demoted account affordance: the signed-in identity and a sign-out
    /// (or exit-demo) action tucked into the toolbar so the booth content
    /// stays front-and-centre.
    @ToolbarContentBuilder
    private var accountToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let profile {
                    Section(profile.name) {
                        Text(profile.email)
                        if !profile.groups.isEmpty {
                            Text(profile.groups.joined(separator: " · "))
                        }
                    }
                }
                if config.isDemoMode {
                    Button {
                        config.disableDemoMode()
                    } label: {
                        Label("Exit Demo Mode", systemImage: "sparkles")
                    }
                } else {
                    Button(role: .destructive) {
                        auth.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } label: {
                Label(profile?.name ?? "Account", systemImage: "person.crop.circle")
            }
            .accessibilityLabel("Account")
        }
    }
    #endif

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Booth")
            if let currentStatus {
                HStack(spacing: Theme.Spacing.small) {
                    BoothStateBadge(state: currentStatus.state)
                    Spacer(minLength: 0)
                    BoothStalenessChip(lastStatusAt: currentStatus.updatedAt)
                    RuntimeModeBadge(mode: currentStatus.runtimeMode)
                }
                Divider().background(Theme.Colors.textSecondary.opacity(0.2))
                if let stats = liveStore.stats {
                    StatRow(label: "Calls today", value: "\(stats.calls.today)")
                    StatRow(label: "In progress", value: "\(stats.calls.inProgress)")
                    StatRow(label: "Messages pending", value: "\(stats.messages.pending)")
                    StatRow(label: "Messages today", value: "\(stats.messages.receivedToday)")
                    StatRow(label: "Live web clients", value: "\(stats.realtime.wsClients)")
                } else {
                    Text("Loading counts…")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    private var currentStatus: BoothStatus? {
        liveStore.status ?? liveStore.stats?.booth
    }

    #if !os(watchOS) && !os(tvOS)
    private var canShowChart: Bool { !liveStore.history.isEmpty || liveStore.lastError != nil }

    @ViewBuilder
    private var historyChartCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Recent activity")
            if liveStore.history.isEmpty, let historyError = liveStore.lastError {
                Text(historyError)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else if liveStore.history.isEmpty {
                ProgressView()
            } else {
                StatusHistoryChart(items: liveStore.history)
                    .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }
    #endif
}

#if !os(watchOS) && !os(tvOS)
private struct StatusHistoryChart: View {
    let items: [BoothStatus]

    var body: some View {
        Chart(items, id: \.updatedAt) { item in
            BarMark(
                x: .value("Time", item.updatedAt),
                y: .value("Active", item.state.isCallActive ? 1 : 0)
            )
            .foregroundStyle(item.state.isCallActive ? Theme.Colors.accent : Theme.Colors.textSecondary.opacity(0.3))
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.Colors.textSecondary.opacity(0.15))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute())
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
    }
}
#endif

private struct BoothStateBadge: View {
    let state: BoothState

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Circle()
                .fill(color(for: state))
                .frame(width: 10, height: 10)
            Text(state.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(Theme.Fonts.bodyLarge.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private func color(for state: BoothState) -> Color {
        switch state {
        case .idle, .dialTone: return Theme.Colors.success
        case .error: return Theme.Colors.error
        default: return Theme.Colors.accent
        }
    }
}

private extension Result {
    var failureOrNil: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
