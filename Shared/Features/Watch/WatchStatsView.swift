//
//  WatchStatsView.swift
//  TelephoneBoothOperatorMobile
//
//  Compact today-only usage stats for the watch: a vertical scroll of
//  small tiles (pickups, messages, completion rate, playbacks, last
//  activity) backed by /v1/stats/overview?window=24h.
//

#if os(watchOS)

import SwiftUI

struct WatchStatsView: View {
    @State private var overview: StatsOverview?
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    private let client: OperatorClient

    init(client: OperatorClient = .shared) {
        self.client = client
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                }
                if let overview {
                    tile(label: "Pickups (24h)", value: "\(overview.pickupsHangups.pickups)")
                    tile(label: "Messages left", value: "\(overview.messages.total)")
                    tile(label: "Completion", value: percent(overview.completionRate))
                    tile(label: "Playbacks", value: "\(overview.playback.totalPlaybacks)")
                    tile(label: "Last activity", value: timeAgo(overview.lastActivityAt))
                } else if !isRefreshing {
                    Text("No data yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .refreshableIfAvailable { await refresh() }
        .task { await refresh() }
    }

    private func tile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            overview = try await client.fetchStatsOverview(window: .last24h)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load stats: \(error.localizedDescription)"
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
