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
    @State private var installationScope: InstallationScope = .current
    @State private var installations: [Installation] = []
    @State private var overview: StatsOverview?
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var refreshToken = 0
    @State private var liveStore: BoothStatusLiveStore

    private let client: OperatorClient

    init(client: OperatorClient = .shared, liveStore: BoothStatusLiveStore? = nil) {
        self.client = client
        _liveStore = State(initialValue: liveStore ?? (client.demoMode ? .demo : .shared))
    }

    var body: some View {
        TVScreen(title: "Stats", systemImage: "chart.bar.fill", accessory: { accessory }, content: {
            TVRangeSelector(window: $window)
            TVInstallationSelector(scope: $installationScope, installations: installations)

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
        .onChange(of: window, initial: true) {
            overview = nil
            errorMessage = nil
        }
        .onChange(of: installationScope) {
            overview = nil
            errorMessage = nil
            refreshToken += 1
            let token = refreshToken
            Task { await refresh(window: window, scope: installationScope, token: token) }
        }
        .autoRefresh(id: window) {
            refreshToken += 1
            let token = refreshToken
            await refresh(window: window, scope: installationScope, token: token)
        }
        .boothStatusLive(liveStore)
        .task {
            installations = (try? await client.fetchInstallations()) ?? []
        }
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
        let interactions = overview.interactionMetrics
        let actions = overview.actionMetrics
        return TVFocusCard {
            VStack(alignment: .leading, spacing: 24) {
                TVCardHeader(
                    title: "\(installationScopeName) · \(window.displayName)",
                    systemImage: "sparkles"
                )
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 4),
                    spacing: 20
                ) {
                    TVStatTile(label: "Pickups", value: number(interactions.total))
                    TVStatTile(label: "No selection", value: number(interactions.noSelection))
                    TVStatTile(label: "Wrong numbers", value: number(actions.wrongNumberAttempts))
                    TVStatTile(label: "Messages left", value: number(interactions.messagesLeft))
                    TVStatTile(
                        label: "Messages listened",
                        value: StatsFormat.optionalNumberString(actions.messagePlaybackStarts)
                    )
                    TVStatTile(
                        label: "Instructions heard",
                        value: StatsFormat.optionalNumberString(actions.instructionPlaybackStarts)
                    )
                    TVStatTile(
                        label: "In progress",
                        value: number(liveInProgress ?? interactions.inProgressNow),
                        emphasize: (liveInProgress ?? interactions.inProgressNow) > 0
                    )
                    TVStatTile(label: "Last activity", value: StatsFormat.timeAgoString(overview.lastActivityAt))
                }
            }
        }
    }

    // MARK: Pickups

    private func callsCard(_ overview: StatsOverview) -> some View {
        let interactions = overview.interactionMetrics
        return TVFocusCard {
            VStack(alignment: .leading, spacing: 16) {
                TVCardHeader(title: "Pickups", systemImage: "phone.connection.fill")
                TVKeyValueRow(key: "Total", value: number(interactions.total))
                TVKeyValueRow(key: "In progress now", value: number(interactions.inProgressNow))
                TVKeyValueRow(key: "No selection", value: number(interactions.noSelection))
                TVKeyValueRow(key: "Messages left", value: number(interactions.messagesLeft))
                TVKeyValueRow(key: "Message left rate", value: StatsFormat.percentString(overview.completionRate))
                TVKeyValueRow(key: "Avg duration", value: StatsFormat.durationString(interactions.averageDurationMs))
                TVKeyValueRow(
                    key: "Longest pickup",
                    value: StatsFormat.durationString(interactions.longestDurationMs)
                )
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
        let perDay = overview.interactionMetrics.perDay
        if !perDay.isEmpty {
            Divider().overlay(Theme.Colors.textSecondary.opacity(0.25))
            Text("Pickups per day (UTC)")
                .font(TVMetrics.Font.rowValue)
                .foregroundStyle(Theme.Colors.textPrimary)
            #if canImport(Charts)
            Chart(perDay, id: \.date) { day in
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
                TVCardHeader(title: "Recordings & moderation", systemImage: "tray.full.fill")
                TVKeyValueRow(key: "Approved messages", value: number(overview.messages.approvedCount))
                TVKeyValueRow(key: "All recordings", value: number(overview.messages.allRecordingsCount))
                TVKeyValueRow(
                    key: "Avg duration",
                    value: StatsFormat.durationString(overview.messages.averageDurationMs)
                )
                TVKeyValueRow(key: "Uploads OK", value: number(overview.uploads.succeeded))
                TVKeyValueRow(key: "Uploads failed", value: failedUploads(overview))
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

    // MARK: Selections & playback

    private func pickupsCard(_ overview: StatsOverview) -> some View {
        let actions = overview.actionMetrics
        let digits = actions.digitsDialedZeroFilled()
        let maxDigit = digits.map(\.count).max() ?? 0
        return TVFocusCard {
            VStack(alignment: .leading, spacing: 16) {
                TVCardHeader(title: "Selections & playback", systemImage: "circle.grid.3x3.fill")
                ForEach(overview.selectionFunnels) { funnel in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(funnel.selectionLabel)
                            .font(TVMetrics.Font.rowValue)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        TVKeyValueRow(key: "Selected", value: number(funnel.selectionCount))
                        TVKeyValueRow(
                            key: funnel.outcomeLabel,
                            value: StatsFormat.optionalNumberString(funnel.outcomeCount)
                        )
                    }
                    .padding(.bottom, 6)
                }
                TVKeyValueRow(key: "Wrong numbers", value: number(actions.wrongNumberAttempts))
                TVKeyValueRow(
                    key: "Total dial attempts",
                    value: number(actions.digitsDialed.values.reduce(0, +))
                )
                if !actions.supportsPlaybackBreakouts {
                    TVKeyValueRow(
                        key: "Combined playback starts",
                        value: StatsFormat.optionalNumberString(actions.totalPlaybackStarts)
                    )
                    Text("Legacy Operator payloads do not split message and instruction playback starts.")
                        .font(TVMetrics.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
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

    private func refresh(
        window requested: StatsWindow,
        scope: InstallationScope = .current,
        token: Int
    ) async {
        isRefreshing = true
        defer {
            // Only the current active request clears the shared spinner flag.
            // A monotonically increasing token survives an A → B → A switch
            // (where `requested == window` would spuriously match), so a
            // superseded task can never blank the newest range mid-load.
            if token == refreshToken { isRefreshing = false }
        }
        do {
            let result = try await client.fetchStatsOverview(
                selection: .window(requested),
                installationScope: scope
            )
            // Ignore results from a range selection that has since changed (the
            // `.task(id:)` was cancelled) so a late/cancelled completion never
            // overwrites the newly selected range or flashes a spurious error.
            guard !Task.isCancelled, token == refreshToken else { return }
            overview = result
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, token == refreshToken else { return }
            errorMessage = "Couldn't load stats: \(error.localizedDescription)"
        }
    }

    /// Live in-progress count from the WebSocket-backed store (when available),
    /// so the headline reflects current booth activity between the slower
    /// historical-overview refreshes.
    private var liveInProgress: Int? {
        liveStore.stats?.interactionsInProgress
    }

    private func number(_ value: Int) -> String {
        StatsFormat.numberFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private var installationScopeName: String {
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
                .accessibilityAddTraits(window == option ? [.isSelected] : [])
            }
        }
    }
}

private struct TVInstallationSelector: View {
    @Binding var scope: InstallationScope
    let installations: [Installation]

    var body: some View {
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
                .font(.system(size: 28, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
        .buttonStyle(TVSegmentButtonStyle(isSelected: scope != .current))
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
