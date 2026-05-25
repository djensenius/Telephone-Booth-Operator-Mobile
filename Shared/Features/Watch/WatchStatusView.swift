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
    @State private var stats: StatsSummary?
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    private let client: OperatorClient

    init(client: OperatorClient = .shared) {
        self.client = client
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage {
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
    }

    private var stateBadge: some View {
        let state = stats?.booth.state ?? .idle
        return HStack(spacing: 10) {
            Image(systemName: state.watchSymbol)
                .font(.title2)
                .foregroundStyle(state.watchTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.watchDisplayName)
                    .font(.headline)
                Text(state.isCallActive ? "Call in progress" : "Standby")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(state.watchTint.opacity(0.18))
        }
    }

    private var statsGrid: some View {
        VStack(spacing: 6) {
            WatchStatRow(label: "Calls today", value: "\(stats?.calls.today ?? 0)")
            WatchStatRow(
                label: "In progress",
                value: "\(stats?.calls.inProgress ?? 0)",
                emphasize: (stats?.calls.inProgress ?? 0) > 0
            )
            WatchStatRow(
                label: "Pending",
                value: "\(stats?.messages.pending ?? 0)",
                emphasize: (stats?.messages.pending ?? 0) > 0
            )
            WatchStatRow(label: "Received today", value: "\(stats?.messages.receivedToday ?? 0)")
            WatchStatRow(label: "WS clients", value: "\(stats?.realtime.wsClients ?? 0)")
        }
    }

    @ViewBuilder
    private var lastUpdatedLine: some View {
        if let generatedAt = stats?.generatedAt {
            Text("Updated \(generatedAt, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func refresh() async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        do {
            let newStats = try await client.fetchStatsSummary()
            stats = newStats
            WidgetSnapshotStore.write(WidgetSnapshot(stats: newStats))
        } catch {
            if stats == nil {
                errorMessage = "Couldn't reach the operator."
            }
        }
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
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(emphasize ? Color.accentColor : .primary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
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
        case .beep: return "circle.fill"
        case .recording: return "record.circle"
        case .uploading: return "icloud.and.arrow.up"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var watchTint: Color {
        switch self {
        case .idle: return .secondary
        case .error: return .red
        case .recording, .uploading, .playingMessage,
             .playingQuestion, .playingInstructions, .dialing,
             .beep, .dialTone:
            return .accentColor
        case .unknown: return .secondary
        }
    }
}

#endif
