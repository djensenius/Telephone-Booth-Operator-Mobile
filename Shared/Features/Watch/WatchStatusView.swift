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

    init(client: OperatorClient = .shared, liveStore: BoothStatusLiveStore? = nil) {
        _liveStore = State(initialValue: liveStore ?? (client.demoMode ? .demo : .shared))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage = liveStore.lastError {
                    BannerView(message: errorMessage, kind: .error)
                }
                stateBadge
                statsGrid
                lastUpdatedLine
            }
            .padding(.horizontal, 4)
        }
        .refreshableIfAvailable {
            await refresh()
        }
        .task {
            await refresh()
        }
        .boothStatusLive(liveStore)
    }

    private var stateBadge: some View {
        let state = liveStore.status?.state ?? liveStore.stats?.booth.state ?? .idle
        return HStack(spacing: 10) {
            Image(systemName: state.watchSymbol)
                .font(.title2)
                .foregroundStyle(state.watchTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.watchDisplayName)
                    .font(.headline)
                Text(state.isCallActive ? "Call in progress" : "Standby")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if let mode = liveStore.status?.runtimeMode ?? liveStore.stats?.booth.runtimeMode, mode.shouldDisplayBadge {
                RuntimeModeBadge(mode: mode)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(state.watchTint.opacity(0.18))
        }
    }

    private var statsGrid: some View {
        VStack(spacing: 6) {
            WatchStatRow(label: "Calls today", value: "\(liveStore.stats?.calls.today ?? 0)")
            WatchStatRow(
                label: "In progress",
                value: "\(liveStore.stats?.calls.inProgress ?? 0)",
                emphasize: (liveStore.stats?.calls.inProgress ?? 0) > 0
            )
            WatchStatRow(
                label: "Pending",
                value: "\(liveStore.stats?.messages.pending ?? 0)",
                emphasize: (liveStore.stats?.messages.pending ?? 0) > 0
            )
            WatchStatRow(label: "Received today", value: "\(liveStore.stats?.messages.receivedToday ?? 0)")
            WatchStatRow(label: "WS clients", value: "\(liveStore.stats?.realtime.wsClients ?? 0)")
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
