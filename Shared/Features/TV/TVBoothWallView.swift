//
//  TVBoothWallView.swift
//  TelephoneBoothOperatorMobile
//
//  Big-screen booth status wall for tvOS. Read-only by design — the
//  remote doesn't translate well to moderation gestures, and message
//  content is deliberately never shown here (that lives in the
//  approve/reject flow). Live booth status and summary counts come from
//  the shared `BoothStatusLiveStore` (WebSocket + 5-second REST fallback);
//  this view additionally polls /v1/stats/overview and /v1/messages every
//  10 seconds to keep the recent-activity strip and overview fresh.
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
                statusOverview
                HStack(alignment: .top, spacing: TVMetrics.cardSpacing) {
                    activityStrip
                        .frame(maxWidth: .infinity)
                    if let overview {
                        overviewStrip(overview: overview)
                            .frame(maxWidth: .infinity)
                    }
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
        .autoRefresh(every: .seconds(10)) { await refresh() }
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
            TVWallConnectionBadge(connection: liveStore.connection)
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

    // MARK: - Current state

    private var statusOverview: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let status = currentStatus
            let state = status?.state ?? .idle
            TVFocusCard {
                HStack(spacing: 34) {
                    Image(systemName: state.tvSymbol)
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(state.tvTint)
                        .frame(width: 118, height: 118)
                        .background {
                            Circle().fill(state.tvTint.opacity(0.16))
                        }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.tvHeadline)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        Text(statusDetail(status, now: context.date))
                            .font(TVMetrics.Font.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer(minLength: 24)
                    HStack(spacing: 16) {
                        TVWallMetric(
                            label: "Calls today",
                            value: liveStore.stats?.calls.today ?? 0,
                            systemImage: "phone.fill"
                        )
                        TVWallMetric(
                            label: "Recorded today",
                            value: liveStore.stats?.messages.receivedToday ?? 0,
                            systemImage: "waveform"
                        )
                        TVWallMetric(
                            label: "To review",
                            value: liveStore.stats?.messages.badgeCount ?? 0,
                            systemImage: "tray.full.fill",
                            emphasize: (liveStore.stats?.messages.badgeCount ?? 0) > 0
                        )
                    }
                    .frame(width: 760)
                }
            }
        }
    }

    private func statusDetail(_ status: BoothStatus?, now: Date) -> String {
        guard let status else { return "Waiting for the first booth update" }
        return "\(status.state.tvDisplayName) · "
            + DurationFormatter.compactString(from: status.heldSince, to: now)
    }

    // MARK: - Recent activity (no message content by design)

    private var activityStrip: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            TVFocusCard {
                VStack(alignment: .leading, spacing: 24) {
                    TVCardHeader(title: "Live context", systemImage: "waveform.path.ecg")
                    HStack(alignment: .top, spacing: 32) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LATEST RECORDING")
                                .font(TVMetrics.Font.label)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(activitySubtitle)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                            .overlay(Theme.Colors.textSecondary.opacity(0.24))
                            .frame(height: 100)
                        let health = healthSummary(now: context.date)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BOOTH HEALTH")
                                .font(TVMetrics.Font.label)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Label(health.label, systemImage: health.systemImage)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(health.tint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(health.detail)
                                .font(TVMetrics.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 130, alignment: .top)
                }
            }
        }
    }

    private func healthSummary(now: Date) -> TVWallHealth {
        guard let envelope = liveStore.systemEnvelope else {
            return TVWallHealth(
                label: "Waiting",
                detail: "No system snapshot yet",
                systemImage: "wave.3.right.circle",
                tint: Theme.Colors.info
            )
        }
        let snapshot = envelope.snapshot
        let routerTemperature = SystemVitals.routerBatteryTemperature(
            in: liveStore.componentSources,
            boothId: envelope.boothId,
            now: now
        )
        let telemetryIsStale =
            now.timeIntervalSince(envelope.receivedAt) >= BoothStalenessThresholds.offlineSeconds
        let severity = SystemVitals.overallSeverity(
            snapshot: snapshot,
            routerTemperature: routerTemperature,
            telemetryIsStale: telemetryIsStale
        )
        let label: String
        let systemImage: String
        switch severity {
        case .nominal:
            (label, systemImage) = ("Nominal", "checkmark.circle.fill")
        case .warn:
            (label, systemImage) = ("Check system", "exclamationmark.triangle.fill")
        case .crit:
            (label, systemImage) = ("Attention", "xmark.octagon.fill")
        }
        return TVWallHealth(
            label: label,
            detail: "\(SystemVitals.formatTemperature(snapshot.cpuTemperatureCelsius)) CPU · "
                + "\(SystemVitals.formatPercent(snapshot.memoryUsedRatio)) memory",
            systemImage: systemImage,
            tint: severity.tint
        )
    }

    private var activitySubtitle: String {
        guard let latest = latestReceivedAt else {
            return recentCount > 0 ? "Recently recorded" : "No recordings yet"
        }
        return StatsFormat.timeAgoString(latest)
    }

    // MARK: - Overview strip

    private func overviewStrip(overview: StatsOverview) -> some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 24) {
                TVCardHeader(title: "Last 7 days", systemImage: "calendar")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2),
                    spacing: 16
                ) {
                    TVWallMiniMetric(
                        label: "Pickups",
                        value: "\(overview.pickupsHangups.pickups)"
                    )
                    TVWallMiniMetric(
                        label: "Recordings",
                        value: "\(overview.messages.allRecordingsCount)"
                    )
                    TVWallMiniMetric(
                        label: "Approved",
                        value: "\(overview.messages.approvedCount)"
                    )
                    TVWallMiniMetric(
                        label: "Completion",
                        value: StatsFormat.percentString(overview.completionRate)
                    )
                }
                .frame(minHeight: 130, alignment: .top)
            }
        }
    }

    // MARK: - Data

    private var currentStatus: BoothStatus? {
        liveStore.status ?? liveStore.stats?.booth
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

// MARK: - Wall metrics

private struct TVWallMetric: View {
    let label: String
    let value: Int
    let systemImage: String
    var emphasize: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label.uppercased(), systemImage: systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value.formatted())
                .font(.system(size: 48, weight: .bold).monospacedDigit())
                .foregroundStyle(emphasize ? Theme.Colors.accent : Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.Colors.background.opacity(0.48))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    emphasize ? Theme.Colors.accent.opacity(0.45) : Color.clear,
                    lineWidth: 2
                )
        )
    }
}

private struct TVWallMiniMetric: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 34, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Colors.background.opacity(0.42))
        )
    }
}

private struct TVWallConnectionBadge: View {
    let connection: BoothStatusLiveStore.ConnectionState

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background {
                Capsule().fill(tint.opacity(0.14))
            }
    }

    private var label: String {
        switch connection {
        case .connecting: return "Connecting"
        case .live: return "Live"
        case .polling: return "Updating"
        case .offline: return "Offline"
        }
    }

    private var systemImage: String {
        switch connection {
        case .connecting: return "ellipsis"
        case .live: return "bolt.fill"
        case .polling: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        }
    }

    private var tint: Color {
        switch connection {
        case .connecting: return Theme.Colors.warning
        case .live: return Theme.Colors.success
        case .polling: return Theme.Colors.info
        case .offline: return Theme.Colors.error
        }
    }
}

private struct TVWallHealth {
    let label: String
    let detail: String
    let systemImage: String
    let tint: Color
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
        case .callUnavailable: return "Call unavailable"
        case .error: return "Error"
        case .unknown(let value): return value.capitalized
        }
    }

    var tvHeadline: String {
        switch self {
        case .idle: return "Ready for the next call"
        case .dialTone: return "A caller is on the line"
        case .dialing: return "Dialing in progress"
        case .playingQuestion: return "Playing a question"
        case .beep: return "Waiting for the response"
        case .recording: return "Recording a message"
        case .uploading: return "Saving the recording"
        case .playingMessage: return "Playing a message"
        case .playingInstructions: return "Playing instructions"
        case .callUnavailable: return "Call unavailable"
        case .error: return "Booth needs attention"
        case .unknown: return "Unknown booth state"
        }
    }

    var tvSymbol: String {
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

    var tvTint: Color {
        switch self {
        case .idle: return Theme.Colors.success
        case .error: return Theme.Colors.error
        case .callUnavailable: return Theme.Colors.warning
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
