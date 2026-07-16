//
//  TVBoothWallView.swift
//  TelephoneBoothOperatorMobile
//
//  Big-screen booth status wall for tvOS. Read-only by design — the
//  remote doesn't translate well to moderation gestures. Polls
//  /v1/stats/summary and /v1/messages every 10 seconds to keep the
//  state badge, stat column, and recent-messages strip fresh.
//

#if os(tvOS)

import SwiftUI

struct TVBoothWallView: View {
    @State private var overview: StatsOverview?
    @State private var recentMessages: [Message] = []
    @State private var errorMessage: String?
    @State private var liveStore: BoothStatusLiveStore

    private let client: OperatorClient

    init(client: OperatorClient = .shared, liveStore: BoothStatusLiveStore = .shared) {
        self.client = client
        _liveStore = State(initialValue: liveStore)
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            VStack(spacing: 48) {
                header
                HStack(alignment: .top, spacing: 60) {
                    statusHero
                        .frame(maxWidth: .infinity)
                    statsColumn
                        .frame(width: 480)
                }
                .padding(.horizontal, 80)
                latestMessagesPanel
                    .padding(.horizontal, 80)
                if let overview {
                    overviewStrip(overview: overview)
                        .padding(.horizontal, 80)
                }
                Spacer()
                if let errorMessage = errorMessage ?? liveStore.lastError {
                    Text(errorMessage)
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.error)
                }
            }
            .padding(.vertical, 60)
        }
        .task { await pollLoop() }
        .boothStatusLive(liveStore)
    }

    private func overviewStrip(overview: StatsOverview) -> some View {
        HStack(spacing: 24) {
            TVStatBlock(
                label: "Pickups (7d)",
                value: "\(overview.pickupsHangups.pickups)"
            )
            TVStatBlock(
                label: "Messages left",
                value: "\(overview.messages.total)"
            )
            TVStatBlock(
                label: "Playbacks",
                value: "\(overview.playback.totalPlaybacks)"
            )
            TVStatBlock(
                label: "Completion",
                value: percentString(overview.completionRate)
            )
        }
    }

    private func percentString(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f%%", value * 100)
    }

    private var header: some View {
        HStack {
            Image(systemName: "phone.connection")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Colors.accent)
            VStack(alignment: .leading) {
                Text("Telephone-Booth Operator")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Booth wall")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if let mode = currentStatus?.runtimeMode, mode.shouldDisplayBadge {
                RuntimeModeBadge(mode: mode)
                    .scaleEffect(1.6)
                    .padding(.trailing, 20)
            }
            if let generatedAt = liveStore.stats?.generatedAt {
                VStack(alignment: .trailing) {
                    Text("Updated")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(generatedAt, style: .time)
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
        .padding(.horizontal, 80)
    }

    private var statusHero: some View {
        let state = currentStatus?.state ?? .idle
        return VStack(spacing: 24) {
            Image(systemName: state.tvSymbol)
                .font(.system(size: 220, weight: .regular))
                .foregroundStyle(state.tvTint)
                .padding(40)
                .background {
                    Circle()
                        .fill(state.tvTint.opacity(0.18))
                }
            Text(state.tvDisplayName)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(state.isCallActive ? "Call in progress" : "Standby")
                .font(.title3)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            TVStatBlock(label: "Calls today", value: "\(liveStore.stats?.calls.today ?? 0)")
            TVStatBlock(
                label: "In progress",
                value: "\(liveStore.stats?.calls.inProgress ?? 0)",
                emphasize: (liveStore.stats?.calls.inProgress ?? 0) > 0
            )
            TVStatBlock(
                label: "Pending moderation",
                value: "\(liveStore.stats?.messages.pending ?? 0)",
                emphasize: (liveStore.stats?.messages.pending ?? 0) > 0
            )
            TVStatBlock(label: "Received today", value: "\(liveStore.stats?.messages.receivedToday ?? 0)")
            TVStatBlock(label: "WS clients", value: "\(liveStore.stats?.realtime.wsClients ?? 0)")
        }
    }

    private var latestMessagesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent messages")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            if recentMessages.isEmpty {
                Text("No recent messages.")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(recentMessages.prefix(3)) { message in
                        TVMessageCard(message: message)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

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
        async let messagesTask: MessageList? = (try? await client.fetchMessages(status: nil, since: nil, limit: 3))
        let (newOverview, newMessages) = await (overviewTask, messagesTask)
        if let newOverview {
            overview = newOverview
        }
        if let newMessages {
            recentMessages = newMessages.items
        }
        if newOverview == nil && newMessages == nil && recentMessages.isEmpty {
            errorMessage = "Couldn't reach the operator."
        } else {
            errorMessage = nil
        }
    }
}

struct TVStatBlock: View {
    let label: String
    let value: String
    var emphasize: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.title3)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 56, weight: .bold).monospacedDigit())
                .foregroundStyle(emphasize ? Theme.Colors.accent : Theme.Colors.textPrimary)
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.Colors.elevatedBackground)
        }
    }
}

struct TVMessageCard: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(message.status.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusColor)
                Spacer()
                Text(message.receivedAt ?? message.createdAt, style: .relative)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if let text = message.latestTranscription?.text, !text.isEmpty {
                Text(text)
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(5)
            } else {
                Text("No transcription yet.")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.Colors.elevatedBackground)
        }
    }

    private var statusColor: Color {
        switch message.status {
        case .approved: return Theme.Colors.success
        case .rejected: return Theme.Colors.error
        case .pending, .received: return Theme.Colors.warning
        case .uploading: return Theme.Colors.textSecondary
        case .unknown: return Theme.Colors.textSecondary
        }
    }
}

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

#endif
