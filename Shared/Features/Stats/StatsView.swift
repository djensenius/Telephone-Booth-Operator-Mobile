//
//  StatsView.swift
//  TelephoneBoothOperatorMobile
//
//  Usage statistics page that mirrors the operator web /stats screen.
//  Reads `/v1/stats/overview?window=` with a 24h/7d/30d/all picker and
//  renders summary tiles, calls-per-day + hourly distribution charts,
//  outcomes + message-status bars, top-questions list, pickups/hangups
//  + digit pad, and an optional per-booth breakdown.
//

import SwiftUI
#if canImport(Charts)
import Charts
#endif

public struct StatsView: View {
    @State private var window: StatsWindow = .last7d
    @State private var overview: StatsOverview?
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    private let client: OperatorClient

    public init(client: OperatorClient = .shared) {
        self.client = client
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                windowPickerCard
                if let errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                }
                if let overview {
                    headlineCard(overview: overview)
                    callsCard(overview: overview)
                    messagesCard(overview: overview)
                    hourlyCard(overview: overview)
                    pickupsHangupsCard(overview: overview)
                    topQuestionsCard(overview: overview)
                    if !overview.boothBreakdown.isEmpty {
                        boothBreakdownCard(overview: overview)
                    }
                } else if isRefreshing {
                    ProgressView("Adding up the numbers…")
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.large)
                }
            }
            .padding(Theme.Spacing.large)
        }
        .background(Theme.Colors.background)
        .task(id: window) { await refresh() }
        .refreshableIfAvailable { await refresh() }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            overview = try await client.fetchStatsOverview(window: window)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load stats: \(error.localizedDescription)"
        }
    }

    // MARK: - Window picker

    private var windowPickerCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(text: "Window")
            Picker("Window", selection: $window) {
                ForEach(StatsWindow.knownCases, id: \.rawValue) { option in
                    Text(option.shortLabel).tag(option)
                }
            }
            #if !os(watchOS)
            .pickerStyle(.segmented)
            #endif
        }
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: .infinity)
        .glassCardBackground()
    }

    // MARK: - Headline

    private func headlineCard(overview: StatsOverview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(text: window.displayName)
            HStack(spacing: Theme.Spacing.small) {
                StatsSummaryTile(
                    label: "Pickups",
                    value: numberFormatter.string(from: NSNumber(value: overview.pickupsHangups.pickups)) ?? "0"
                )
                StatsSummaryTile(
                    label: "Messages left",
                    value: numberFormatter.string(from: NSNumber(value: overview.messages.total)) ?? "0"
                )
                StatsSummaryTile(
                    label: "Completion",
                    value: percentString(overview.completionRate)
                )
            }
            HStack(spacing: Theme.Spacing.small) {
                StatsSummaryTile(
                    label: "Booth playbacks",
                    value: numberFormatter.string(from: NSNumber(value: overview.playback.totalPlaybacks)) ?? "0"
                )
                StatsSummaryTile(
                    label: "Last activity",
                    value: timeAgoString(overview.lastActivityAt)
                )
                StatsSummaryTile(
                    label: "In progress",
                    value: numberFormatter.string(from: NSNumber(value: overview.calls.inProgress)) ?? "0"
                )
            }
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity)
        .glassCardBackground()
    }

    // MARK: - Calls

    private func callsCard(overview: StatsOverview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Calls")
            StatRow(
                label: "Total",
                value: numberFormatter.string(from: NSNumber(value: overview.calls.total)) ?? "0"
            )
            StatRow(
                label: "Completed",
                value: numberFormatter.string(from: NSNumber(value: overview.calls.completed)) ?? "0"
            )
            StatRow(
                label: "Avg duration",
                value: durationString(overview.calls.averageDurationMs)
            )
            StatRow(
                label: "Longest call",
                value: durationString(overview.calls.longestDurationMs)
            )
            Text("Outcomes").font(Theme.Fonts.bodyMedium.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            outcomeBars(overview: overview)
            Text("Calls per day (UTC)").font(Theme.Fonts.bodyMedium.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            perDayChart(overview: overview)
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity)
        .glassCardBackground()
    }

    private func outcomeBars(overview: StatsOverview) -> some View {
        let entries = overview.outcomesInDisplayOrder()
        let max = entries.map(\.count).max() ?? 0
        return VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            if entries.isEmpty {
                Text("No completed calls in this window.")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(entries, id: \.key) { entry in
                    StatsBarRow(
                        label: StatsOverview.outcomeLabel(entry.key),
                        value: entry.count,
                        max: max
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func perDayChart(overview: StatsOverview) -> some View {
        #if canImport(Charts)
        if overview.calls.perDay.isEmpty {
            Text("No data in this window.")
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
        } else {
            Chart(overview.calls.perDay, id: \.date) { day in
                BarMark(
                    x: .value("Date", day.date),
                    y: .value("Total", day.total)
                )
                .foregroundStyle(Theme.Colors.accent)
                .annotation(position: .top) {
                    if day.total > 0 {
                        Text("\(day.completed)/\(day.total)")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisValueLabel {
                        if let dateString = value.as(String.self) {
                            Text(shortDateLabel(dateString))
                        }
                    }
                }
            }
        }
        #else
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            ForEach(overview.calls.perDay, id: \.date) { day in
                StatRow(label: day.date, value: "\(day.completed)/\(day.total)")
            }
        }
        #endif
    }

    // MARK: - Messages

    private func messagesCard(overview: StatsOverview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Messages")
            StatRow(
                label: "Left",
                value: numberFormatter.string(from: NSNumber(value: overview.messages.total)) ?? "0"
            )
            StatRow(
                label: "Avg duration",
                value: durationString(overview.messages.averageDurationMs)
            )
            StatRow(
                label: "Booth playbacks",
                value: numberFormatter.string(from: NSNumber(value: overview.playback.totalPlaybacks)) ?? "0"
            )
            Text("By status").font(Theme.Fonts.bodyMedium.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            statusBars(overview: overview)
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity)
        .glassCardBackground()
    }

    private func statusBars(overview: StatsOverview) -> some View {
        let entries = overview.statusesInDisplayOrder()
        let max = entries.map(\.count).max() ?? 0
        return VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            if entries.isEmpty {
                Text("No messages in this window.")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(entries, id: \.key) { entry in
                    StatsBarRow(
                        label: StatsOverview.statusLabel(entry.key),
                        value: entry.count,
                        max: max
                    )
                }
            }
        }
    }

    // MARK: - Hourly

    private func hourlyCard(overview: StatsOverview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Hour of day")
            if let hour = overview.busiest.hour {
                Text("Busiest hour: \(formatHour(hour))" +
                     (overview.busiest.dayOfWeek
                        .flatMap(StatsOverview.dayOfWeekLabel)
                        .map { " · \($0)" } ?? ""))
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            hourlyChart(overview: overview)
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity)
        .glassCardBackground()
    }

    @ViewBuilder
    private func hourlyChart(overview: StatsOverview) -> some View {
        #if canImport(Charts)
        Chart(overview.hourly) { bucket in
            BarMark(
                x: .value("Hour", bucket.hour),
                y: .value("Calls", bucket.calls)
            )
            .foregroundStyle(Theme.Colors.accent)
        }
        .frame(height: 140)
        .chartXAxis {
            AxisMarks(values: stride(from: 0, through: 23, by: 3).map { $0 })
        }
        #else
        VStack(alignment: .leading, spacing: 2) {
            ForEach(overview.hourly) { bucket in
                StatRow(label: "\(bucket.hour):00", value: "\(bucket.calls)")
            }
        }
        #endif
    }

    // MARK: - Pickups / hangups

    private func pickupsHangupsCard(overview: StatsOverview) -> some View {
        let digits = overview.pickupsHangups.digitsDialedZeroFilled()
        let maxDigit = digits.map(\.count).max() ?? 0
        return VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Pickups & hangups")
            StatRow(
                label: "Pickups",
                value: numberFormatter.string(from: NSNumber(value: overview.pickupsHangups.pickups)) ?? "0"
            )
            StatRow(
                label: "Hangups",
                value: numberFormatter.string(from: NSNumber(value: overview.pickupsHangups.hangups)) ?? "0"
            )
            StatRow(
                label: "Uploads succeeded",
                value: numberFormatter.string(from: NSNumber(value: overview.uploads.succeeded)) ?? "0"
            )
            StatRow(
                label: "Uploads failed",
                value: failedUploadsLabel(overview: overview)
            )
            Text("Digits dialed").font(Theme.Fonts.bodyMedium.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 4),
                    count: 5
                ),
                spacing: 4
            ) {
                ForEach(digits, id: \.digit) { entry in
                    StatsDigitTile(digit: entry.digit, count: entry.count, max: maxDigit)
                }
            }
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity)
        .glassCardBackground()
    }

    private func failedUploadsLabel(overview: StatsOverview) -> String {
        let count = numberFormatter.string(from: NSNumber(value: overview.uploads.failed)) ?? "0"
        if let rate = overview.uploads.failureRate {
            return "\(count) (\(percentString(rate)))"
        }
        return count
    }

    // MARK: - Top questions

    private func topQuestionsCard(overview: StatsOverview) -> some View {
        StatsTopQuestionsCard(overview: overview)
    }

    // MARK: - Booth breakdown

    private func boothBreakdownCard(overview: StatsOverview) -> some View {
        StatsBoothBreakdownCard(overview: overview)
    }

    // MARK: - Formatting

    private var numberFormatter: NumberFormatter { StatsFormat.numberFormatter }

    private func percentString(_ value: Double?) -> String {
        StatsFormat.percentString(value)
    }

    private func durationString(_ value: Double?) -> String {
        StatsFormat.durationString(value)
    }

    private func timeAgoString(_ date: Date?) -> String {
        StatsFormat.timeAgoString(date)
    }

    private func formatHour(_ hour: Int) -> String {
        StatsFormat.formatHour(hour)
    }

    private func shortDateLabel(_ isoDay: String) -> String {
        StatsFormat.shortDateLabel(isoDay)
    }
}

#Preview {
    StatsView(client: .shared)
}
