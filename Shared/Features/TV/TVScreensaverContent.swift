//
//  TVScreensaverContent.swift
//  TelephoneBoothOperatorMobile
//
//  Shared tvOS visualization content for the dashboard and ambient
//  screensaver. Ambient cards render large on pure black so idle OLED
//  pixels stay dark (burn-in safe).
//

#if os(tvOS)

import SwiftUI
#if canImport(Charts)
import Charts
#endif

/// Fixed light palette for the ambient screensaver. The screensaver always
/// renders on a pure-black background, so it must not borrow the dashboard
/// theme's neutral text colors — in a light theme (e.g. Catppuccin Latte)
/// `Theme.Colors.textPrimary` resolves to a dark ink that is nearly invisible
/// on black. These stay light regardless of the selected theme.
private enum TVAmbient {
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let grid = Color.white.opacity(0.12)
}

/// One item in the screensaver playlist. Built fresh from live data every
/// cycle so the wall always reflects the current booth.
struct TVSpotlight: Identifiable {
    let id: String
    let kind: Kind

    enum Kind {
        case status(state: BoothState, detail: String)
        case metric(value: String, label: String, systemImage: String, emphasized: Bool)
        case callsChart(days: [StatsOverview.PerDay])
    }
}

/// Renders a single spotlight. Text is intentionally dimmed a touch and the
/// caller roams/fades it around the screen to avoid static high-contrast
/// regions.
struct TVSpotlightCard: View {
    let spotlight: TVSpotlight

    var body: some View {
        Group {
            switch spotlight.kind {
            case let .status(state, detail):
                statusCard(state: state, detail: detail)
            case let .metric(value, label, systemImage, emphasized):
                metricCard(value: value, label: label, systemImage: systemImage, emphasized: emphasized)
            case let .callsChart(days):
                chartCard(days: days)
            }
        }
        .opacity(0.92)
    }

    // MARK: - Status

    private func statusCard(state: BoothState, detail: String) -> some View {
        VStack(spacing: 40) {
            Image(systemName: state.tvSymbol)
                .font(.system(size: 150, weight: .regular))
                .foregroundStyle(state.tvTint)
                .frame(height: 190)
                .padding(48)
                .background { Circle().fill(state.tvTint.opacity(0.16)) }
            VStack(spacing: 14) {
                Text(state.tvDisplayName)
                    .font(.system(size: 96, weight: .bold))
                    .foregroundStyle(TVAmbient.textPrimary)
                Text(detail)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(TVAmbient.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Metric

    private func metricCard(value: String, label: String, systemImage: String, emphasized: Bool) -> some View {
        VStack(spacing: 30) {
            Image(systemName: systemImage)
                .font(.system(size: 92, weight: .regular))
                .foregroundStyle(emphasized ? Theme.Colors.accent : TVAmbient.textSecondary)
            Text(value)
                .font(.system(size: 210, weight: .bold).monospacedDigit())
                .foregroundStyle(emphasized ? Theme.Colors.accent : TVAmbient.textPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 38, weight: .semibold))
                .tracking(3)
                .foregroundStyle(TVAmbient.textSecondary)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Calls chart

    private func chartCard(days: [StatsOverview.PerDay]) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("CALLS · LAST 7 DAYS")
                .font(.system(size: 34, weight: .semibold))
                .tracking(3)
                .foregroundStyle(TVAmbient.textSecondary)
            chart(days: days)
                .frame(width: 900, height: 420)
        }
    }

    @ViewBuilder
    private func chart(days: [StatsOverview.PerDay]) -> some View {
        #if canImport(Charts)
        Chart(days, id: \.date) { day in
            BarMark(
                x: .value("Date", StatsFormat.shortDateLabel(day.date)),
                y: .value("Calls", day.total)
            )
            .foregroundStyle(Theme.Colors.accent.gradient)
            .cornerRadius(8)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(TVAmbient.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(TVAmbient.grid)
                AxisValueLabel()
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(TVAmbient.textSecondary)
            }
        }
        #else
        HStack(alignment: .bottom, spacing: 20) {
            ForEach(days, id: \.date) { day in
                let peak = max(1, days.map(\.total).max() ?? 1)
                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.Colors.accent)
                        .frame(height: CGFloat(day.total) / CGFloat(peak) * 340 + 6)
                    Text(StatsFormat.shortDateLabel(day.date))
                        .font(.system(size: 24))
                        .foregroundStyle(TVAmbient.textSecondary)
                }
            }
        }
        #endif
    }
}

struct TVRecentCallsCard: View {
    let items: [BoothStatus]

    private var calls: [BoothActivityCall] {
        items.activityCalls()
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            TVFocusCard {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            TVCardHeader(
                                title: "Recent calls",
                                systemImage: "phone.fill"
                            )
                            Text(summary(at: context.date))
                                .font(TVMetrics.Font.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer(minLength: 20)
                        Label("Height shows duration", systemImage: "clock")
                            .font(TVMetrics.Font.caption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    if calls.isEmpty {
                        Text("No calls in this window")
                            .font(TVMetrics.Font.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        recentCallsChart(now: context.date)
                    }
                }
            }
        }
    }

    private func recentCallsChart(now: Date) -> some View {
        Chart {
            ForEach(calls) { call in
                BarMark(
                    x: .value("Call started", call.startedAt),
                    y: .value("Duration", durationMinutes(for: call, at: now)),
                    width: .fixed(5)
                )
                .foregroundStyle(Theme.Colors.accent.opacity(call.isInProgress ? 0.82 : 0.38))
                .cornerRadius(3)

                PointMark(
                    x: .value("Call started", call.startedAt),
                    y: .value("Duration", durationMinutes(for: call, at: now))
                )
                .symbolSize(call.isInProgress ? 180 : 110)
                .foregroundStyle(Theme.Colors.accent)
            }
        }
        .frame(height: 230)
        .chartXScale(domain: timeDomain)
        .chartYScale(domain: 0...durationCeiling(at: now))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.08))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute())
                            .font(TVMetrics.Font.caption.monospacedDigit())
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.12))
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(durationAxisLabel(minutes))
                            .font(TVMetrics.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(Theme.Colors.background.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityLabel(Text("Recent calls by start time and duration"))
    }

    private var timeDomain: ClosedRange<Date> {
        let start = items.first?.heldSince ?? Date()
        let observedEnd = items.last?.updatedAt ?? start
        let end = Swift.max(observedEnd, start.addingTimeInterval(60))
        let padding = max(30, end.timeIntervalSince(start) * 0.015)
        return start.addingTimeInterval(-padding)...end.addingTimeInterval(padding)
    }

    private func summary(at date: Date) -> String {
        guard let first = items.first, let last = items.last else {
            return "No recent status yet"
        }
        let span = DurationFormatter.compactString(
            from: first.heldSince,
            to: last.updatedAt
        )
        guard !calls.isEmpty else { return "Quiet across \(span)" }
        let completed = calls.filter { !$0.isInProgress }
        let countLabel = "\(calls.count) \(calls.count == 1 ? "call" : "calls")"
        let liveLabel = calls.contains(where: \.isInProgress) ? " · live now" : ""
        guard !completed.isEmpty else { return countLabel + liveLabel }
        let average = completed.reduce(0) { $0 + $1.duration(at: date) }
            / Double(completed.count)
        return "\(countLabel) · \(compactDuration(average)) average\(liveLabel)"
    }

    private func durationCeiling(at date: Date) -> Double {
        max(1, calls.map { durationMinutes(for: $0, at: date) }.max() ?? 1) * 1.16
    }

    private func durationMinutes(for call: BoothActivityCall, at date: Date) -> Double {
        max(call.duration(at: date) / 60, 0.05)
    }

    private func durationAxisLabel(_ minutes: Double) -> String {
        guard minutes > 0 else { return "0" }
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(Int(minutes.rounded()))m" }
        return "\(Int((minutes / 60).rounded()))h"
    }

    private func compactDuration(_ seconds: TimeInterval) -> String {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        return DurationFormatter.compactString(
            from: start,
            to: start.addingTimeInterval(seconds)
        )
    }
}

// MARK: - Playlist builder

enum TVScreensaverPlaylist {
    /// Assemble the spotlight sequence from the latest live data. Only items
    /// with meaningful data are included, and booth status is added *only when
    /// something is happening* (never the idle state).
    static func build(
        status: BoothStatus?,
        stats: StatsSummary?,
        overview: StatsOverview?
    ) -> [TVSpotlight] {
        var items: [TVSpotlight] = []

        if let status, let statusItem = statusSpotlight(for: status.state) {
            items.append(statusItem)
        }

        if let stats {
            items.append(contentsOf: spotlights(for: stats))
        }

        if let overview {
            items.append(contentsOf: spotlights(for: overview))
        }

        return items
    }

    private static func spotlights(for stats: StatsSummary) -> [TVSpotlight] {
        var items: [TVSpotlight] = []

        if stats.calls.today > 0 {
            items.append(metric("calls-today", "\(stats.calls.today)", "Calls today", "phone.fill"))
        }
        if stats.calls.inProgress > 0 {
            items.append(
                metric(
                    "in-progress",
                    "\(stats.calls.inProgress)",
                    "In progress",
                    "phone.connection.fill",
                    emphasized: true
                )
            )
        }
        if stats.messages.pending > 0 {
            items.append(
                metric(
                    "pending",
                    "\(stats.messages.pending)",
                    "Awaiting review",
                    "tray.full.fill",
                    emphasized: true
                )
            )
        }
        if stats.messages.receivedToday > 0 {
            items.append(metric("received", "\(stats.messages.receivedToday)", "Received today", "envelope.fill"))
        }

        return items
    }

    private static func spotlights(for overview: StatsOverview) -> [TVSpotlight] {
        var items: [TVSpotlight] = []

        if let rate = overview.completionRate, rate > 0 {
            items.append(
                metric("completion", StatsFormat.percentString(rate), "Completion rate", "checkmark.seal.fill")
            )
        }
        if overview.pickupsHangups.pickups > 0 {
            items.append(
                metric("pickups", "\(overview.pickupsHangups.pickups)", "Pickups · 7 days", "hand.raised.fill")
            )
        }
        if overview.playback.totalPlaybacks > 0 {
            items.append(
                metric(
                    "playbacks",
                    "\(overview.playback.totalPlaybacks)",
                    "Playbacks · 7 days",
                    "speaker.wave.2.fill"
                )
            )
        }
        if overview.calls.perDay.contains(where: { $0.total > 0 }) {
            items.append(TVSpotlight(id: "calls-chart", kind: .callsChart(days: overview.calls.perDay)))
        }

        return items
    }

    /// A booth is "doing something" for any non-idle, known state. Idle and
    /// unknown states are deliberately omitted so the wall only lights up with
    /// status when there is genuine activity.
    static func isHappening(_ state: BoothState) -> Bool {
        switch state {
        case .idle, .unknown:
            return false
        case .dialTone, .dialing, .playingQuestion, .beep, .recording,
             .uploading, .playingMessage, .playingInstructions, .callUnavailable, .error:
            return true
        }
    }

    /// The status spotlight for a state, or `nil` when nothing is happening.
    /// Shared by the rotation and the live "jump to activity" interrupt.
    static func statusSpotlight(for state: BoothState) -> TVSpotlight? {
        guard isHappening(state) else { return nil }
        return TVSpotlight(id: "status", kind: .status(state: state, detail: statusDetail(state)))
    }

    private static func statusDetail(_ state: BoothState) -> String {
        switch state {
        case .error:
            return "Needs attention"
        default:
            return state.isCallActive ? "Call in progress" : "Booth active"
        }
    }

    private static func metric(
        _ id: String,
        _ value: String,
        _ label: String,
        _ symbol: String,
        emphasized: Bool = false
    ) -> TVSpotlight {
        TVSpotlight(
            id: id,
            kind: .metric(value: value, label: label, systemImage: symbol, emphasized: emphasized)
        )
    }
}

#endif
