//
//  TVBoothWallView.swift
//  TelephoneBoothOperatorMobile
//
//  Big-screen booth status wall for tvOS. Read-only by design — the
//  remote doesn't translate well to moderation gestures, and message
//  content is deliberately never shown here (that lives in the
//  approve/reject flow). Polls /v1/stats/summary and /v1/messages every
//  10 seconds to keep the state hero, KPI column, and recent-activity
//  strip fresh.
//
//  Laid out with `TVDashboardKit` so everything stays inside the tvOS
//  title-safe area and the whole wall scrolls (focusable cards) instead
//  of running the header off the top and the overview strip off the
//  bottom.
//

#if os(tvOS)

import SwiftUI

struct TVBoothWallView: View {
    @State private var overview: StatsOverview?
    @State private var recentCount: Int = 0
    @State private var latestReceivedAt: Date?
    @State private var errorMessage: String?
    @State private var liveStore: BoothStatusLiveStore

    private let client: OperatorClient

    init(client: OperatorClient = .shared, liveStore: BoothStatusLiveStore? = nil) {
        self.client = client
        _liveStore = State(initialValue: liveStore ?? (client.demoMode ? .demo : .shared))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVMetrics.sectionSpacing) {
                header
                HStack(alignment: .top, spacing: TVMetrics.cardSpacing) {
                    statusHero
                        .frame(maxWidth: .infinity)
                    kpiColumn
                        .frame(width: 560)
                }
                activityStrip
                if let overview {
                    overviewStrip(overview: overview)
                }
                if let errorMessage = errorMessage ?? liveStore.lastError {
                    TVBanner(message: errorMessage)
                }
            }
            .frame(maxWidth: TVMetrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, TVMetrics.screenPaddingH)
            .padding(.top, TVMetrics.screenPaddingTop)
            .padding(.bottom, TVMetrics.screenPaddingBottom)
        }
        .scrollClipDisabled()
        .background(TVBackground())
        .task { await pollLoop() }
        .boothStatusLive(liveStore)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 22) {
            Image(systemName: "phone.connection.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Telephone-Booth Operator")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Booth wall")
                    .font(TVMetrics.Font.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 24)
            if let mode = currentStatus?.runtimeMode, mode.shouldDisplayBadge {
                RuntimeModeBadge(mode: mode)
                    .scaleEffect(1.5)
                    .padding(.trailing, 16)
            }
            if let generatedAt = liveStore.stats?.generatedAt {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Updated")
                        .font(TVMetrics.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(generatedAt, style: .time)
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
    }

    // MARK: - Hero

    private var statusHero: some View {
        let state = currentStatus?.state ?? .idle
        return TVFocusCard {
            VStack(spacing: 28) {
                Image(systemName: state.tvSymbol)
                    .font(.system(size: 150, weight: .regular))
                    .foregroundStyle(state.tvTint)
                    .frame(height: 200)
                    .padding(36)
                    .background {
                        Circle().fill(state.tvTint.opacity(0.18))
                    }
                Text(state.tvDisplayName)
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(state.isCallActive ? "Call in progress" : "Standby")
                    .font(TVMetrics.Font.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - KPI column

    private var kpiColumn: some View {
        VStack(spacing: 20) {
            TVBoothStatRow(label: "Calls today", value: "\(liveStore.stats?.calls.today ?? 0)")
            TVBoothStatRow(
                label: "In progress",
                value: "\(liveStore.stats?.calls.inProgress ?? 0)",
                emphasize: (liveStore.stats?.calls.inProgress ?? 0) > 0
            )
            TVBoothStatRow(
                label: "Pending moderation",
                value: "\(liveStore.stats?.messages.pending ?? 0)",
                emphasize: (liveStore.stats?.messages.pending ?? 0) > 0
            )
            TVBoothStatRow(label: "Received today", value: "\(liveStore.stats?.messages.receivedToday ?? 0)")
            TVBoothStatRow(label: "WS clients", value: "\(liveStore.stats?.realtime.wsClients ?? 0)")
        }
    }

    // MARK: - Recent activity (no message content by design)

    private var activityStrip: some View {
        TVFocusCard {
            HStack(alignment: .center, spacing: 28) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent messages")
                        .font(TVMetrics.Font.cardTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(activitySubtitle)
                        .font(TVMetrics.Font.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                Text("\(liveStore.stats?.messages.pending ?? 0)")
                    .font(TVMetrics.Font.statValue)
                    .foregroundStyle(
                        (liveStore.stats?.messages.pending ?? 0) > 0
                            ? Theme.Colors.accent : Theme.Colors.textSecondary
                    )
                Text("awaiting\nreview")
                    .font(TVMetrics.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var activitySubtitle: String {
        if recentCount == 0 {
            return "No messages recorded yet."
        }
        let noun = recentCount == 1 ? "message" : "messages"
        if let latest = latestReceivedAt {
            return "\(recentCount) \(noun) · newest \(latest.formatted(.relative(presentation: .named)))"
        }
        return "\(recentCount) \(noun) recorded"
    }

    // MARK: - Overview strip

    private func overviewStrip(overview: StatsOverview) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 4),
            spacing: 20
        ) {
            TVStatTile(label: "Pickups (7d)", value: "\(overview.pickupsHangups.pickups)")
            TVStatTile(label: "Messages left", value: "\(overview.messages.total)")
            TVStatTile(label: "Playbacks", value: "\(overview.playback.totalPlaybacks)")
            TVStatTile(label: "Completion", value: StatsFormat.percentString(overview.completionRate))
        }
    }

    // MARK: - Data

    private var currentStatus: BoothStatus? {
        liveStore.status ?? liveStore.stats?.booth
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func refresh() async {
        async let overviewTask: StatsOverview? = (try? await client.fetchStatsOverview(window: .last7d))
        async let messagesTask: MessageList? = (try? await client.fetchMessages(status: nil, since: nil, limit: 5))
        let (newOverview, newMessages) = await (overviewTask, messagesTask)
        if let newOverview {
            overview = newOverview
        }
        if let newMessages {
            recentCount = newMessages.items.count
            latestReceivedAt = newMessages.items
                .compactMap { $0.receivedAt ?? $0.createdAt }
                .max()
        }
        if newOverview == nil && newMessages == nil {
            errorMessage = "Couldn't reach the operator."
        } else {
            errorMessage = nil
        }
    }
}

// MARK: - KPI row

private struct TVBoothStatRow: View {
    let label: String
    let value: String
    var emphasize: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(label)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(size: 52, weight: .bold).monospacedDigit())
                .foregroundStyle(emphasize ? Theme.Colors.accent : Theme.Colors.textPrimary)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 30)
        .background(
            RoundedRectangle(cornerRadius: TVMetrics.cardCornerRadius, style: .continuous)
                .fill(Theme.Colors.elevatedBackground.opacity(0.6))
        )
    }
}

// MARK: - Booth state presentation

extension BoothState {
    var tvDisplayName: String {
        switch self {
        case .idle: return "Idle"
        case .dialTone: return "Dial tone"
        case .dialing: return "Dialing"
        case .playingQuestion: return "Playing question"
        case .beep: return "Beep"
        case .recording: return "Recording"
        case .uploading: return "Uploading"
        case .playingMessage: return "Playing message"
        case .playingInstructions: return "Instructions"
        case .error: return "Error"
        case .unknown(let value): return value.capitalized
        }
    }

    var tvSymbol: String {
        switch self {
        case .idle: return "phone.fill"
        case .dialTone, .dialing: return "phone.arrow.up.right"
        case .playingQuestion, .playingMessage, .playingInstructions:
            return "speaker.wave.2.fill"
        case .beep: return "circle.fill"
        case .recording: return "record.circle"
        case .uploading: return "icloud.and.arrow.up"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var tvTint: Color {
        switch self {
        case .idle: return Theme.Colors.textSecondary
        case .error: return Theme.Colors.error
        case .recording, .uploading, .playingMessage,
             .playingQuestion, .playingInstructions, .dialing,
             .beep, .dialTone:
            return Theme.Colors.accent
        case .unknown: return Theme.Colors.textSecondary
        }
    }
}

#Preview {
    TVBoothWallView(client: .demo, liveStore: .demo)
}

#endif
