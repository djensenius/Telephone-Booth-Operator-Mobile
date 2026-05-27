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
    @State private var profile: OperatorMe?
    @State private var stats: StatsSummary?
    @State private var history: [BoothStatus] = []
    @State private var historyError: String?
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var systemEnvelope: BoothSystemSnapshotEnvelope?

    private let client: OperatorClient

    public init(client: OperatorClient = .shared) {
        self.client = client
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                if let errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                }
                operatorCard
                statsCard
                SystemVitalsStrip(
                    snapshot: systemEnvelope?.snapshot,
                    receivedAt: systemEnvelope?.receivedAt
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
        .refreshableIfAvailable {
            await refresh()
        }
        .task {
            await refresh()
        }
    }

    public func refresh() async {
        isRefreshing = true
        errorMessage = nil
        historyError = nil
        defer { isRefreshing = false }
        async let meTask: OperatorMe? = (try? await client.fetchMe())
        async let statsTask: StatsSummary? = (try? await client.fetchStatsSummary())
        async let historyTask: StatusHistory? = (try? await client.fetchStatusHistory(limit: 200))
        async let systemTask: BoothSystemSnapshotEnvelope? = (try? await client.fetchCurrentSystemEnvelope())
        let (newMe, newStats, newHistory, newSystem) = await (meTask, statsTask, historyTask, systemTask)
        profile = newMe ?? profile
        stats = newStats ?? stats
        if let newStats {
            WidgetSnapshotStore.write(WidgetSnapshot(stats: newStats))
        }
        if let newHistory {
            history = newHistory.items
        } else if history.isEmpty {
            historyError = "Couldn't load recent status history."
        }
        if let newSystem {
            systemEnvelope = newSystem
        }
        if newMe == nil && newStats == nil {
            errorMessage = "Couldn't reach the operator. Check your network or server URL in Settings."
        }
    }

    private var operatorCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(text: "Signed in as")
            if let profile {
                Text(profile.name)
                    .font(Theme.Fonts.headerLarge())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(profile.email)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                if !profile.groups.isEmpty {
                    Text(profile.groups.joined(separator: " · "))
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

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Booth")
            if let stats {
                HStack(spacing: Theme.Spacing.small) {
                    BoothStateBadge(state: stats.booth.state)
                    Spacer(minLength: 0)
                    BoothStalenessChip(lastStatusAt: stats.booth.updatedAt)
                    RuntimeModeBadge(mode: stats.booth.runtimeMode)
                }
                Divider().background(Theme.Colors.textSecondary.opacity(0.2))
                StatRow(label: "Calls today", value: "\(stats.calls.today)")
                StatRow(label: "In progress", value: "\(stats.calls.inProgress)")
                StatRow(label: "Messages pending", value: "\(stats.messages.pending)")
                StatRow(label: "Messages today", value: "\(stats.messages.receivedToday)")
                StatRow(label: "Live web clients", value: "\(stats.realtime.wsClients)")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    #if !os(watchOS) && !os(tvOS)
    private var canShowChart: Bool { !history.isEmpty || historyError != nil }

    @ViewBuilder
    private var historyChartCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Recent activity")
            if let historyError {
                Text(historyError)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else if history.isEmpty {
                ProgressView()
            } else {
                StatusHistoryChart(items: history)
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
