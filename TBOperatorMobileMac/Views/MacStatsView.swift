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
    @State private var preset: StatsWindow = .last7d
    @State private var selection: StatsRangeSelection = .default
    @State private var customStart: Date = Date().addingTimeInterval(-7 * 24 * 60 * 60)
    @State private var customEnd: Date = Date()
    @State private var endIsNow: Bool = true
    @State private var filters: [MetricFilter] = []
    @State private var overview: StatsOverview?
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var isPresentingCustom = false
    @State private var newFilterName = ""

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
                Picker("Window", selection: $preset) {
                    ForEach(StatsWindow.knownCases, id: \.rawValue) { option in
                        Text(option.shortLabel).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
            ToolbarItem(placement: .automatic) {
                rangeMenu
            }
        }
        .onChange(of: preset) { _, newValue in
            selection = .window(newValue)
        }
        .task(id: selection) { await refresh() }
        .task { await loadFilters() }
        .sheet(isPresented: $isPresentingCustom) {
            customRangeSheet
        }
    }

    private var rangeMenu: some View {
        Menu {
            Button("Custom range…") { isPresentingCustom = true }
            if !filters.isEmpty {
                Divider()
                ForEach(filters) { filter in
                    Button(filter.name) { apply(filter: filter) }
                }
                Divider()
                Menu("Delete filter") {
                    ForEach(filters) { filter in
                        Button(filter.name, role: .destructive) {
                            Task { await delete(filter: filter) }
                        }
                    }
                }
            }
        } label: {
            Label(selection.displayName, systemImage: "calendar")
        }
    }

    private var customRangeSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom range")
                .font(Theme.Fonts.headerLarge())
            DatePicker(
                "Start",
                selection: $customStart,
                in: ...customEnd,
                displayedComponents: [.date, .hourAndMinute]
            )
            Toggle("End = now", isOn: $endIsNow)
            if !endIsNow {
                DatePicker(
                    "End",
                    selection: $customEnd,
                    in: customStart...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
            HStack {
                TextField("Save as…", text: $newFilterName)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { Task { await saveCurrentFilter() } }
                    .disabled(newFilterName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresentingCustom = false }
                Button("Apply") {
                    applyCustomRange()
                    isPresentingCustom = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            overview = try await client.fetchStatsOverview(selection: selection)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load stats: \(error.localizedDescription)"
        }
    }

    private func loadFilters() async {
        filters = (try? await client.fetchMetricFilters()) ?? []
    }

    private func applyCustomRange() {
        selection = .custom(
            start: customStart,
            endIsNow: endIsNow,
            end: endIsNow ? nil : customEnd
        )
    }

    private func apply(filter: MetricFilter) {
        selection = filter.selection
        if case .window(let window) = filter.selection {
            preset = window
        }
        if case .custom(let start, let isNow, let end) = filter.selection {
            if let start { customStart = start }
            endIsNow = isNow
            if let end { customEnd = end }
        }
    }

    private func saveCurrentFilter() async {
        let name = newFilterName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newFilterName = ""
        applyCustomRange()
        if let created = try? await client.createMetricFilter(
            MetricFilterInput(name: name, selection: selection)
        ) {
            filters.append(created)
        }
    }

    private func delete(filter: MetricFilter) async {
        try? await client.deleteMetricFilter(id: filter.id)
        filters.removeAll { $0.id == filter.id }
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
