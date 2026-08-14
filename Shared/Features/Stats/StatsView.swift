// swiftlint:disable file_length
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
    @State private var selection: StatsRangeSelection = .default
    @State private var filters: [MetricFilter] = []
    @State private var installationScope: InstallationScope = .current
    @State private var installations: [Installation] = []
    @State private var overview: StatsOverview?
    @State private var errorMessage: String?
    @State private var controlsError: String?
    @State private var isRefreshing = false
    @State private var refreshGeneration = 0

    private let client: OperatorClient

    public init(client: OperatorClient = .shared) {
        self.client = client
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                #if !os(watchOS)
                StatsInstallationScopePicker(
                    scope: $installationScope,
                    installations: installations
                )
                #endif
                StatsRangeControls(
                    selection: $selection,
                    filters: filters,
                    onSave: { name in Task { await saveCurrentFilter(named: name) } },
                    onDelete: { filter in Task { await delete(filter: filter) } }
                )
                if let controlsError {
                    BannerView(message: controlsError, kind: .error)
                }
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
        .autoRefresh(id: selection) { await refresh() }
        .task {
            await loadFilters()
            await loadInstallations()
        }
        .onChange(of: installationScope) {
            Task { await refresh() }
        }
        .refreshableIfAvailable { await refresh() }
    }
}

extension StatsView {
    private func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let requestedSelection = selection
        let requestedScope = installationScope
        isRefreshing = true
        defer {
            if generation == refreshGeneration {
                isRefreshing = false
            }
        }
        do {
            let result = try await client.fetchStatsOverview(
                selection: requestedSelection,
                installationScope: requestedScope
            )
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            overview = result
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            errorMessage = "Couldn't load stats: \(error.localizedDescription)"
        }
    }

    private func loadFilters() async {
        do {
            filters = try await client.fetchMetricFilters()
            controlsError = nil
        } catch {
            controlsError = "Couldn't load saved filters: \(error.localizedDescription)"
        }
    }

    private func loadInstallations() async {
        do {
            installations = try await client.fetchInstallations()
        } catch {
            controlsError = "Couldn't load installations: \(error.localizedDescription)"
        }
    }

    private func saveCurrentFilter(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let created = try await client.createMetricFilter(
                MetricFilterInput(name: trimmed, selection: selection)
            )
            filters.append(created)
            controlsError = nil
        } catch {
            controlsError = "Couldn't save filter: \(error.localizedDescription)"
        }
    }

    private func delete(filter: MetricFilter) async {
        do {
            try await client.deleteMetricFilter(id: filter.id)
            filters.removeAll { $0.id == filter.id }
            controlsError = nil
        } catch {
            controlsError = "Couldn't delete filter: \(error.localizedDescription)"
        }
    }

    // MARK: - Headline

    private func headlineCard(overview: StatsOverview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(text: selection.displayName)
            Text(scopeName)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: Theme.Spacing.small) {
                StatsSummaryTile(
                    label: "Pickups",
                    value: numberFormatter.string(from: NSNumber(value: overview.pickupsHangups.pickups)) ?? "0"
                )
                StatsSummaryTile(
                    label: "Approved messages",
                    value: numberFormatter.string(
                        from: NSNumber(value: overview.messages.approvedCount)
                    ) ?? "0"
                )
                StatsSummaryTile(
                    label: "Completion",
                    value: percentString(overview.completionRate)
                )
            }
            HStack(spacing: Theme.Spacing.small) {
                StatsSummaryTile(
                    label: "All recordings",
                    value: numberFormatter.string(
                        from: NSNumber(value: overview.messages.allRecordingsCount)
                    ) ?? "0"
                )
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
            SectionHeader(text: "Recordings")
            StatRow(
                label: "Approved messages",
                value: numberFormatter.string(
                    from: NSNumber(value: overview.messages.approvedCount)
                ) ?? "0"
            )
            StatRow(
                label: "All recordings",
                value: numberFormatter.string(
                    from: NSNumber(value: overview.messages.allRecordingsCount)
                ) ?? "0"
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
}

extension StatsView {
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

    private var scopeName: String {
        switch installationScope {
        case .current:
            return "Current Installation"
        case .all:
            return "All Installations"
        case .installation(let id):
            return installations.first(where: { $0.id == id })?.name ?? "Historical Installation"
        }
    }
}

#if !os(watchOS)
private struct StatsInstallationScopePicker: View {
    @Binding var scope: InstallationScope
    let installations: [Installation]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(text: "Installation")
            Menu {
                Button("Current Installation") { scope = .current }
                if !installations.isEmpty {
                    Divider()
                    ForEach(installations) { installation in
                        Button(installation.name) {
                            scope = installation.isActive
                                ? .current
                                : .installation(installation.id)
                        }
                    }
                }
                Divider()
                Button("All Installations") { scope = .all }
            } label: {
                Label(scopeTitle, systemImage: "building.2")
                    .font(Theme.Fonts.bodySmall.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: .infinity)
        .glassCardBackground()
    }

    private var scopeTitle: String {
        switch scope {
        case .current:
            return "Current Installation"
        case .all:
            return "All Installations"
        case .installation(let id):
            return installations.first(where: { $0.id == id })?.name ?? "Historical Installation"
        }
    }
}
#endif

#Preview {
    StatsView(client: .demo)
}
