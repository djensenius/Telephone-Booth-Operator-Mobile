//
//  MacStatsView.swift
//  TBOperatorMobileMac
//
//  Mac-native rewrite of the stats screen. Instead of the iOS stack of
//  full-width glass cards, this uses a centred toolbar window picker and
//  lays native `GroupBox` sections into a responsive multi-column grid so
//  wide Mac windows are actually used. Data, formatting, and charts reuse
//  the shared `StatsOverview` / `StatsFormat` helpers.
//

#if os(macOS)

import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct MacStatsView: View {
    @State private var window: StatsWindow = .last7d
    @State private var overview: StatsOverview?
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    private let client: OperatorClient

    init(client: OperatorClient = .shared) {
        self.client = client
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                }
                if let overview {
                    summaryGrid(overview)
                    sectionsGrid(overview)
                } else if isRefreshing {
                    ProgressView("Adding up the numbers…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.background)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Window", selection: $window) {
                    ForEach(StatsWindow.knownCases, id: \.rawValue) { option in
                        Text(option.shortLabel).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
        }
        .task(id: window) { await refresh() }
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

    // MARK: - Summary metrics

    private func summaryGrid(_ overview: StatsOverview) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
            spacing: 12
        ) {
            MacMetricTile(label: "Pickups", value: num(overview.pickupsHangups.pickups))
            MacMetricTile(label: "Messages left", value: num(overview.messages.total))
            MacMetricTile(label: "Completion", value: StatsFormat.percentString(overview.completionRate))
            MacMetricTile(label: "Booth playbacks", value: num(overview.playback.totalPlaybacks))
            MacMetricTile(label: "Last activity", value: StatsFormat.timeAgoString(overview.lastActivityAt))
            MacMetricTile(label: "In progress", value: num(overview.calls.inProgress))
        }
    }

    // MARK: - Section grid

    private func sectionsGrid(_ overview: StatsOverview) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 360), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 16
        ) {
            callsSection(overview)
            messagesSection(overview)
            hourlySection(overview)
            pickupsSection(overview)
            topQuestionsSection(overview)
            if !overview.boothBreakdown.isEmpty {
                boothSection(overview)
            }
        }
    }

    private func callsSection(_ overview: StatsOverview) -> some View {
        GroupBox("Calls") {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                LabeledContent("Total", value: num(overview.calls.total))
                LabeledContent("Completed", value: num(overview.calls.completed))
                LabeledContent("Avg duration", value: StatsFormat.durationString(overview.calls.averageDurationMs))
                LabeledContent("Longest call", value: StatsFormat.durationString(overview.calls.longestDurationMs))
                Divider()
                Text("Outcomes").font(.headline)
                bars(overview.outcomesInDisplayOrder().map {
                    (StatsOverview.outcomeLabel($0.key), $0.count)
                }, empty: "No completed calls in this window.")
                Text("Calls per day (UTC)").font(.headline)
                perDayChart(overview)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func messagesSection(_ overview: StatsOverview) -> some View {
        GroupBox("Messages") {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                LabeledContent("Left", value: num(overview.messages.total))
                LabeledContent("Avg duration", value: StatsFormat.durationString(overview.messages.averageDurationMs))
                LabeledContent("Booth playbacks", value: num(overview.playback.totalPlaybacks))
                Divider()
                Text("By status").font(.headline)
                bars(overview.statusesInDisplayOrder().map {
                    (StatsOverview.statusLabel($0.key), $0.count)
                }, empty: "No messages in this window.")
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hourlySection(_ overview: StatsOverview) -> some View {
        GroupBox("Hour of day") {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                if let hour = overview.busiest.hour {
                    let day = overview.busiest.dayOfWeek
                        .flatMap(StatsOverview.dayOfWeekLabel)
                        .map { " · \($0)" } ?? ""
                    Text("Busiest hour: \(StatsFormat.formatHour(hour))\(day)")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                hourlyChart(overview)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pickupsSection(_ overview: StatsOverview) -> some View {
        let digits = overview.pickupsHangups.digitsDialedZeroFilled()
        let maxDigit = digits.map(\.count).max() ?? 0
        return GroupBox("Pickups & hangups") {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                LabeledContent("Pickups", value: num(overview.pickupsHangups.pickups))
                LabeledContent("Hangups", value: num(overview.pickupsHangups.hangups))
                LabeledContent("Uploads succeeded", value: num(overview.uploads.succeeded))
                LabeledContent("Uploads failed", value: failedUploads(overview))
                Divider()
                Text("Digits dialed").font(.headline)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5),
                    spacing: 4
                ) {
                    ForEach(digits, id: \.digit) { entry in
                        StatsDigitTile(digit: entry.digit, count: entry.count, max: maxDigit)
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func topQuestionsSection(_ overview: StatsOverview) -> some View {
        GroupBox("Top questions") {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                if overview.topQuestions.isEmpty {
                    Text("No question responses in this window.")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    let maxCount = overview.topQuestions.map(\.messageCount).max() ?? 0
                    ForEach(Array(overview.topQuestions.enumerated()), id: \.element.id) { index, question in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(index + 1).")
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text(question.prompt).lineLimit(2)
                                Spacer()
                                Text(num(question.messageCount)).monospacedDigit()
                            }
                            .font(Theme.Fonts.bodyMedium)
                            StatsBarTrack(value: question.messageCount, max: maxCount)
                        }
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func boothSection(_ overview: StatsOverview) -> some View {
        GroupBox("By booth") {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                ForEach(overview.boothBreakdown) { entry in
                    LabeledContent {
                        Text("\(entry.calls) calls").monospacedDigit()
                    } label: {
                        Text(entry.boothId)
                        Text("Last seen \(StatsFormat.timeAgoString(entry.lastSeenAt))")
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Charts

    @ViewBuilder
    private func perDayChart(_ overview: StatsOverview) -> some View {
        if overview.calls.perDay.isEmpty {
            Text("No data in this window.")
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
        } else {
            Chart(overview.calls.perDay, id: \.date) { day in
                BarMark(x: .value("Date", day.date), y: .value("Total", day.total))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .frame(height: 160)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisValueLabel {
                        if let dateString = value.as(String.self) {
                            Text(StatsFormat.shortDateLabel(dateString))
                        }
                    }
                }
            }
        }
    }

    private func hourlyChart(_ overview: StatsOverview) -> some View {
        Chart(overview.hourly) { bucket in
            BarMark(x: .value("Hour", bucket.hour), y: .value("Calls", bucket.calls))
                .foregroundStyle(Theme.Colors.accent)
        }
        .frame(height: 140)
        .chartXAxis {
            AxisMarks(values: stride(from: 0, through: 23, by: 3).map { $0 })
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func bars(_ entries: [(String, Int)], empty: String) -> some View {
        if entries.isEmpty {
            Text(empty)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
        } else {
            let maxValue = entries.map(\.1).max() ?? 0
            ForEach(entries, id: \.0) { label, value in
                StatsBarRow(label: label, value: value, max: maxValue)
            }
        }
    }

    private func num(_ value: Int) -> String {
        StatsFormat.numberFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func failedUploads(_ overview: StatsOverview) -> String {
        let count = num(overview.uploads.failed)
        if let rate = overview.uploads.failureRate {
            return "\(count) (\(StatsFormat.percentString(rate)))"
        }
        return count
    }
}

/// A single headline metric rendered as a native bordered tile.
private struct MacMetricTile: View {
    let label: String
    let value: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    MacStatsView(client: .demo)
        .frame(width: 820, height: 600)
}

#endif
