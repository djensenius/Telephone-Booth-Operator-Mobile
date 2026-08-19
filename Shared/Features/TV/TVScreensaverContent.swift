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

struct TVCallsTodayCard: View {
    let sessions: [CallSession]
    let dayStartedAt: Date?
    let isLoaded: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let series = CallsTodaySeries(
                sessions: sessions,
                dayStartedAt: dayStartedAt
                    ?? Calendar.current.startOfDay(for: context.date),
                now: context.date
            )
            TVFocusCard {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            TVCardHeader(
                                title: "Calls today",
                                systemImage: "phone.fill"
                            )
                            Text(summary(for: series))
                                .font(TVMetrics.Font.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer(minLength: 20)
                        Label("Cumulative total", systemImage: "chart.line.uptrend.xyaxis")
                            .font(TVMetrics.Font.caption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    if !isLoaded {
                        ProgressView("Loading calls...")
                            .font(TVMetrics.Font.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 230)
                    } else if series.total == 0 {
                        Text("No calls since midnight")
                            .font(TVMetrics.Font.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 230)
                    } else {
                        callsTodayChart(series)
                    }
                }
            }
        }
    }

    private func callsTodayChart(_ series: CallsTodaySeries) -> some View {
        Chart {
            ForEach(series.points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Calls", point.count)
                )
                .interpolationMethod(.stepEnd)
                .lineStyle(StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Theme.Colors.accent)
            }
            if let endpoint = series.points.last {
                PointMark(
                    x: .value("Time", endpoint.date),
                    y: .value("Calls", endpoint.count)
                )
                .symbolSize(170)
                .foregroundStyle(Theme.Colors.accent)
                .annotation(position: .topLeading) {
                    Text("\(series.total)")
                        .font(TVMetrics.Font.body.monospacedDigit().weight(.bold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .frame(height: 230)
        .chartXScale(domain: series.dayStartedAt...xAxisEnd(for: series))
        .chartYScale(domain: 0...max(1, series.total + 1))
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
            AxisMarks(position: .leading, values: series.yAxisValues) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.12))
                AxisValueLabel {
                    if let count = value.as(Int.self) {
                        Text("\(count)")
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
        .accessibilityLabel(Text("Cumulative calls today"))
        .accessibilityValue(Text("\(series.total) calls since midnight"))
    }

    private func summary(for series: CallsTodaySeries) -> String {
        "\(series.total) \(series.total == 1 ? "call" : "calls") since midnight"
    }

    private func xAxisEnd(for series: CallsTodaySeries) -> Date {
        max(series.through, series.dayStartedAt.addingTimeInterval(60))
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
