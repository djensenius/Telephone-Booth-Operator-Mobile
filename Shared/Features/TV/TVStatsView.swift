//
//  TVStatsView.swift
//  TelephoneBoothOperatorMobile
//
//  Big-screen Stats dashboard for tvOS. Read-only. Uses `TVDashboardKit`
//  so the screen scrolls (focusable cards) and the range selector reads
//  clearly when focused instead of washing the label out to white.
//

#if os(tvOS)

import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct TVStatsView: View {
    @State private var window: StatsWindow = .last7d
    @State private var overview: StatsOverview?
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var liveStore: BoothStatusLiveStore

    private let client: OperatorClient

    init(client: OperatorClient = .shared, liveStore: BoothStatusLiveStore? = nil) {
        self.client = client
        _liveStore = State(initialValue: liveStore ?? (client.demoMode ? .demo : .shared))
    }

    var body: some View {
        TVScreen(title: "Stats", systemImage: "chart.bar.fill", accessory: { accessory }, content: {
            TVRangeSelector(window: $window)

            if let errorMessage {
                TVBanner(message: errorMessage)
            }

            if let overview {
                headline(overview)
                TVCardGrid {
                    callsCard(overview)
                    messagesCard(overview)
                    pickupsCard(overview)
                    topQuestionsCard(overview)
                }
            } else if isRefreshing {
                TVFocusCard {
                    HStack(spacing: 20) {
                        ProgressView()
                        Text("Adding up the numbers…")
                            .font(TVMetrics.Font.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        })
        .task(id: window) {
            // Refresh immediately when the range changes, then keep a
            // wall-mounted Stats tab live (and retry a failed first load)
            // by re-polling on a slow cadence while the tab is on screen.
            // Clear the previous range's numbers first so they are never shown
            // relabelled under the newly selected window while the new (or a
            // failed) request is in flight.
            overview = nil
            let requested = window
            while !Task.isCancelled {
                await refresh(window: requested)
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .boothStatusLive(liveStore)
    }

    @ViewBuilder
    private var accessory: some View {
        if let generatedAt = overview?.generatedAt {
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

    // MARK: Headline KPIs

    private func headline(_ overview: StatsOverview) -> some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 24) {
                TVCardHeader(title: window.displayName, systemImage: "sparkles")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3),
                    spacing: 20
                ) {
                    TVStatTile(label: "Pickups", value: number(overview.pickupsHangups.pickups))
                    TVStatTile(label: "Messages left", value: number(overview.messages.total))
                    TVStatTile(
                        label: "Completion",
                        value: StatsFormat.percentString(overview.completionRate)
                    )
                    TVStatTile(label: "Booth playbacks", value: number(overview.playback.totalPlaybacks))
                    TVStatTile(
                        label: "Last activity",
                        value: StatsFormat.timeAgoString(overview.lastActivityAt)
                    )
                    TVStatTile(
                        label: "In progress",
                        value: number(liveInProgress ?? overview.calls.inProgress),
                        emphasize: (liveInProgress ?? overview.calls.inProgress) > 0
                    )
                }
            }
        }
    }

    // MARK: Calls

    private func callsCard(_ overview: StatsOverview) -> some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 16) {
                TVCardHeader(title: "Calls", systemImage: "phone.connection.fill")
                TVKeyValueRow(key: "Total", value: number(overview.calls.total))
                TVKeyValueRow(key: "Completed", value: number(overview.calls.completed))
                TVKeyValueRow(key: "Avg duration", value: StatsFormat.durationString(overview.calls.averageDurationMs))
                TVKeyValueRow(key: "Longest call", value: StatsFormat.durationString(overview.calls.longestDurationMs))

                let outcomes = overview.outcomesInDisplayOrder()
                if !outcomes.isEmpty {
                    Divider().overlay(Theme.Colors.textSecondary.opacity(0.25))
                    Text("Outcomes")
                        .font(TVMetrics.Font.rowValue)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    let maxOutcome = outcomes.map(\.count).max() ?? 0
                    ForEach(outcomes, id: \.key) { entry in
                        TVBarRow(
                            label: StatsOverview.outcomeLabel(entry.key),
                            value: entry.count,
                            max: maxOutcome
                        )
                    }
                }

                perDayChart(overview)
            }
        }
    }

    @ViewBuilder
    private func perDayChart(_ overview: StatsOverview) -> some View {
        if !overview.calls.perDay.isEmpty {
            Divider().overlay(Theme.Colors.textSecondary.opacity(0.25))
            Text("Calls per day (UTC)")
                .font(TVMetrics.Font.rowValue)
                .foregroundStyle(Theme.Colors.textPrimary)
            #if canImport(Charts)
            Chart(overview.calls.perDay, id: \.date) { day in
                BarMark(
                    x: .value("Date", StatsFormat.shortDateLabel(day.date)),
                    y: .value("Total", day.total)
                )
                .foregroundStyle(Theme.Colors.accent)
            }
            .frame(height: 220)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(TVMetrics.Font.caption)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(TVMetrics.Font.caption)
                }
            }
            #endif
        }
    }

    // MARK: Messages

    private func messagesCard(_ overview: StatsOverview) -> some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 16) {
                TVCardHeader(title: "Messages", systemImage: "tray.full.fill")
                TVKeyValueRow(key: "Left", value: number(overview.messages.total))
                TVKeyValueRow(
                    key: "Avg duration",
                    value: StatsFormat.durationString(overview.messages.averageDurationMs)
                )
                TVKeyValueRow(key: "Booth playbacks", value: number(overview.playback.totalPlaybacks))

                let statuses = overview.statusesInDisplayOrder()
                if !statuses.isEmpty {
                    Divider().overlay(Theme.Colors.textSecondary.opacity(0.25))
                    Text("By status")
                        .font(TVMetrics.Font.rowValue)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    let maxStatus = statuses.map(\.count).max() ?? 0
                    ForEach(statuses, id: \.key) { entry in
                        TVBarRow(
                            label: StatsOverview.statusLabel(entry.key),
                            value: entry.count,
                            max: maxStatus
                        )
                    }
                }
            }
        }
    }

    // MARK: Pickups & hangups

    private func pickupsCard(_ overview: StatsOverview) -> some View {
        let digits = overview.pickupsHangups.digitsDialedZeroFilled()
        let maxDigit = digits.map(\.count).max() ?? 0
        return TVFocusCard {
            VStack(alignment: .leading, spacing: 16) {
                TVCardHeader(title: "Pickups & hangups", systemImage: "hand.raised.fill")
                TVKeyValueRow(key: "Pickups", value: number(overview.pickupsHangups.pickups))
                TVKeyValueRow(key: "Hangups", value: number(overview.pickupsHangups.hangups))
                TVKeyValueRow(key: "Uploads OK", value: number(overview.uploads.succeeded))
                TVKeyValueRow(key: "Uploads failed", value: failedUploads(overview))
                Divider().overlay(Theme.Colors.textSecondary.opacity(0.25))
                Text("Digits dialed")
                    .font(TVMetrics.Font.rowValue)
                    .foregroundStyle(Theme.Colors.textPrimary)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                    spacing: 12
                ) {
                    ForEach(digits, id: \.digit) { entry in
                        TVDigitTile(digit: entry.digit, count: entry.count, max: maxDigit)
                    }
                }
            }
        }
    }

    private func failedUploads(_ overview: StatsOverview) -> String {
        let count = number(overview.uploads.failed)
        if let rate = overview.uploads.failureRate {
            return "\(count) (\(StatsFormat.percentString(rate)))"
        }
        return count
    }

    // MARK: Top questions

    private func topQuestionsCard(_ overview: StatsOverview) -> some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 16) {
                TVCardHeader(title: "Top questions", systemImage: "questionmark.bubble.fill")
                if overview.topQuestions.isEmpty {
                    Text("No question responses in this window.")
                        .font(TVMetrics.Font.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    let maxCount = overview.topQuestions.map(\.messageCount).max() ?? 0
                    ForEach(Array(overview.topQuestions.prefix(5).enumerated()), id: \.element.id) { index, question in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text("\(index + 1).")
                                    .font(TVMetrics.Font.rowValue)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text(question.prompt)
                                    .font(TVMetrics.Font.body)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(2)
                                Spacer(minLength: 12)
                                Text(number(question.messageCount))
                                    .font(TVMetrics.Font.rowValue)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            TVProgressLine(value: question.messageCount, max: maxCount)
                        }
                    }
                }
            }
        }
    }

    // MARK: Data

    private func refresh(window requested: StatsWindow) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await client.fetchStatsOverview(window: requested)
            // Ignore results from a range selection that has since changed (the
            // `.task(id:)` was cancelled) so a late/cancelled completion never
            // overwrites the newly selected range or flashes a spurious error.
            guard !Task.isCancelled, requested == window else { return }
            overview = result
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, requested == window else { return }
            errorMessage = "Couldn't load stats: \(error.localizedDescription)"
        }
    }

    /// Live in-progress count from the WebSocket-backed store (when available),
    /// so the headline reflects current booth activity between the slower
    /// historical-overview refreshes.
    private var liveInProgress: Int? {
        liveStore.stats?.calls.inProgress
    }

    private func number(_ value: Int) -> String {
        StatsFormat.numberFormatter.string(from: NSNumber(value: value)) ?? "0"
    }
}

// MARK: - Range selector

private struct TVRangeSelector: View {
    @Binding var window: StatsWindow

    var body: some View {
        HStack(spacing: 20) {
            ForEach(StatsWindow.knownCases, id: \.rawValue) { option in
                Button {
                    window = option
                } label: {
                    Text(option.shortLabel)
                        .font(.system(size: 30, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                }
                .buttonStyle(TVSegmentButtonStyle(isSelected: window == option))
            }
        }
    }
}

/// Segmented-control button style with an unmistakable selected state and
/// a focus treatment that keeps the label readable (accent ring + lift)
/// rather than filling the pill solid white.
private struct TVSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SegmentBody(configuration: configuration, isSelected: isSelected)
    }

    private struct SegmentBody: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(foreground)
                .background(
                    Capsule().fill(fill)
                )
                .overlay(
                    Capsule().strokeBorder(
                        Theme.Colors.accent.opacity(isFocused ? 1 : 0),
                        lineWidth: 4
                    )
                )
                .scaleEffect(isFocused ? 1.06 : 1)
                .animation(.easeOut(duration: 0.16), value: isFocused)
                .animation(.easeOut(duration: 0.16), value: isSelected)
        }

        private var foreground: Color {
            if isSelected { return .white }
            return Theme.Colors.textPrimary
        }

        private var fill: Color {
            if isSelected { return Theme.Colors.accent }
            if isFocused { return Theme.Colors.elevatedBackground }
            return Theme.Colors.elevatedBackground.opacity(0.6)
        }
    }
}

// MARK: - Small primitives

private struct TVDigitTile: View {
    let digit: String
    let count: Int
    let max: Int

    var body: some View {
        let intensity = max > 0 ? Double(count) / Double(max) : 0
        VStack(spacing: 4) {
            Text(digit)
                .font(.system(size: 34, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("\(count)")
                .font(TVMetrics.Font.caption.monospacedDigit())
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Colors.accent.opacity(0.15 + intensity * 0.5))
        )
    }
}

private struct TVProgressLine: View {
    let value: Int
    let max: Int

    var body: some View {
        GeometryReader { proxy in
            let ratio = max > 0 ? Double(value) / Double(max) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.accent.opacity(0.18))
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: Swift.max(6, proxy.size.width * ratio))
            }
        }
        .frame(height: 12)
    }
}

#Preview {
    TVStatsView(client: .demo)
}

#endif
