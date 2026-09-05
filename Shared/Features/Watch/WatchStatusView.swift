//
//  WatchStatusView.swift
//  TelephoneBoothOperatorMobile
//
//  watchOS-tailored booth status. Single scroll page with the booth
//  state badge at the top and a stat trio below. Refresh pulls
//  /v1/stats/summary and stores the widget snapshot so the
//  complication picks up the latest values.
//

#if os(watchOS)

import SwiftUI

struct WatchStatusView: View {
    @State private var isRefreshing = false
    @State private var liveStore: BoothStatusLiveStore
    @Environment(\.automaticRefreshEnabled) private var automaticRefreshEnabled
    @Environment(\.scenePhase) private var scenePhase

    init(client: OperatorClient = .shared, liveStore: BoothStatusLiveStore? = nil) {
        _liveStore = State(initialValue: liveStore ?? (client.demoMode ? .demo : .shared))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage = liveStore.lastError {
                    BannerView(message: errorMessage, kind: .error)
                }
                if let state = liveStore.status?.state ?? liveStore.stats?.booth.state {
                    stateBadge(state)
                } else if liveStore.lastError == nil {
                    ProgressView("Loading booth status")
                } else {
                    Text("Booth status unavailable.").font(.caption)
                    Button("Retry") { Task { await refresh() } }
                        .disabled(isRefreshing)
                }
                if let stats = liveStore.stats {
                    statsGrid(stats)
                } else {
                    Text("Counts unavailable until loaded.")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                lastUpdatedLine
            }
            .padding(.horizontal, 4)
        }
        .refreshableIfAvailable {
            await refresh()
        }
        .boothStatusLive(liveStore)
        .automaticRefreshEnabled(automaticRefreshEnabled && scenePhase == .active)
    }

    private func stateBadge(_ state: BoothState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: state.watchSymbol)
                    .font(.title3)
                    .foregroundStyle(state.watchTint)
                Text(state.watchDisplayName)
                    .font(.headline)
            }
            Text(state.watchActivityDescription)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let mode = liveStore.status?.runtimeMode ?? liveStore.stats?.booth.runtimeMode, mode.shouldDisplayBadge {
                RuntimeModeBadge(mode: mode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(state.watchTint.opacity(0.18))
        }
    }

    private func statsGrid(_ stats: StatsSummary) -> some View {
        VStack(spacing: 6) {
            WatchStatRow(
                label: "Pickups today",
                value: "\(stats.interactionsToday)"
            )
            WatchStatRow(
                label: "In progress",
                value: "\(stats.interactionsInProgress)",
                emphasize: stats.interactionsInProgress > 0
            )
            WatchStatRow(
                label: "Pending",
                value: "\(stats.messages.pending)",
                emphasize: stats.messages.pending > 0
            )
            WatchStatRow(label: "Received today", value: "\(stats.messages.receivedToday)")
            WatchStatRow(label: "WS clients", value: "\(stats.realtime.wsClients)")
            if let fan = liveStore.systemEnvelope?.snapshot.fan {
                WatchStatRow(label: "Fan command", value: fan.commandDescription ?? "—")
                WatchStatRow(label: "Fan measured", value: fan.measuredSpeedDescription)
                if let coolingState = fan.coolingStateDescription {
                    WatchStatRow(label: "Fan state", value: coolingState)
                }
            }
        }
    }

    @ViewBuilder
    private var lastUpdatedLine: some View {
        if let generatedAt = liveStore.stats?.generatedAt {
            Text("Updated \(generatedAt, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await liveStore.refreshNow()
    }
}

struct WatchStatRow: View {
    let label: String
    let value: String
    var emphasize: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(emphasize ? Theme.Colors.accent : Theme.Colors.textPrimary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Colors.elevatedBackground)
        }
    }
}

extension BoothState {
    var watchActivityDescription: String {
        switch self {
        case .idle: return "Standby"
        case .dialTone: return "Ready to dial"
        case .error: return "Booth reported an error"
        case .callUnavailable: return "Call unavailable"
        case .unknown: return "Unknown booth state"
        default: return "Call in progress"
        }
    }

    var watchDisplayName: String {
        switch self {
        case .idle: return "Idle"
        case .dialTone: return "Dial tone"
        case .dialing: return "Dialing"
        case .playingQuestion: return "Question"
        case .beep: return "Beep"
        case .recording: return "Recording"
        case .uploading: return "Uploading"
        case .playingMessage: return "Playing"
        case .playingInstructions: return "Instructions"
        case .callUnavailable: return "Unavailable"
        case .error: return "Error"
        case .unknown(let value): return value.capitalized
        }
    }

    var watchSymbol: String {
        switch self {
        case .idle: return "phone.fill"
        case .dialTone, .dialing: return "phone.arrow.up.right"
        case .playingQuestion, .playingMessage, .playingInstructions:
            return "speaker.wave.2.fill"
        case .callUnavailable: return "phone.down.fill"
        case .beep: return "circle.fill"
        case .recording: return "record.circle"
        case .uploading: return "icloud.and.arrow.up"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var watchTint: Color {
        switch self {
        case .idle: return Theme.Colors.textSecondary
        case .error: return Theme.Colors.error
        case .recording, .uploading, .playingMessage,
             .playingQuestion, .playingInstructions, .dialing,
             .beep, .dialTone, .callUnavailable:
            return Theme.Colors.accent
        case .unknown: return Theme.Colors.textSecondary
        }
    }
}

#endif
