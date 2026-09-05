//
//  WatchStatsView.swift
//  TelephoneBoothOperatorMobile
//
//  Compact rolling 24-hour usage stats for the watch: a vertical scroll of
//  small tiles for interaction breakouts and current booth activity,
//  backed by /v1/stats/overview?window=24h.
//

#if os(watchOS)

import SwiftUI

struct WatchStatsView: View {
    @State private var overview: StatsOverview?
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var hasLoaded = false

    private let client: OperatorClient

    init(client: OperatorClient = .shared) {
        self.client = client
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                    Button("Retry") { Task { await refresh() } }
                        .disabled(isRefreshing)
                }
                if let overview {
                    let interactions = overview.interactionMetrics
                    let actions = overview.actionMetrics
                    tile(label: "Pickups (24h)", value: StatsFormat.numberString(interactions.total))
                    tile(label: "No selection", value: StatsFormat.numberString(interactions.noSelection))
                    tile(label: "Wrong numbers", value: StatsFormat.numberString(actions.wrongNumberAttempts))
                    tile(label: "Messages left", value: StatsFormat.numberString(interactions.messagesLeft))
                    tile(
                        label: "Messages listened",
                        value: StatsFormat.optionalNumberString(actions.messagePlaybackStarts)
                    )
                    tile(
                        label: "Instructions heard",
                        value: StatsFormat.optionalNumberString(actions.instructionPlaybackStarts)
                    )
                    tile(label: "In progress", value: StatsFormat.numberString(interactions.inProgressNow))
                    tile(label: "Message left rate", value: percent(overview.completionRate))
                    tile(label: "Last activity", value: timeAgo(overview.lastActivityAt))
                } else if !hasLoaded && errorMessage == nil {
                    ProgressView("Loading stats")
                } else if errorMessage == nil {
                    Text("No data yet.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .refreshableIfAvailable { await refresh() }
        .autoRefresh { await refresh() }
    }

    private func tile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Colors.elevatedBackground)
        )
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let loaded = try await client.fetchStatsOverview(window: .last24h)
            try Task.checkCancellation()
            overview = loaded
            hasLoaded = true
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = "Couldn't refresh stats. Displayed data may be out of date."
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f%%", value * 100)
    }

    private func timeAgo(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let delta = max(0, Int(Date().timeIntervalSince(date)))
        if delta < 60 { return "\(delta)s" }
        if delta < 3600 { return "\(delta / 60)m" }
        if delta < 86_400 * 2 { return "\(delta / 3600)h" }
        return "\(delta / 86_400)d"
    }
}

#endif
