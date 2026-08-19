//
//  StatusDashboardView.swift
//  TelephoneBoothOperatorMobile
//
//  Compact live booth status, health, metrics, and recent activity.
//
import SwiftUI
#if canImport(Charts)
import Charts
#endif

public struct StatusDashboardView: View {
    @State private var auth = AuthManager.shared
    @State private var config = AppConfig.shared
    @State private var profile: OperatorMe?
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var liveStore: BoothStatusLiveStore

    private let client: OperatorClient

    public init(client: OperatorClient = .shared, liveStore: BoothStatusLiveStore? = nil) {
        self.client = client
        _liveStore = State(initialValue: liveStore ?? (client.demoMode ? .demo : .shared))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                if let displayError {
                    BannerView(message: displayError, kind: .error)
                }
                overviewCard
                secondaryCards
            }
            .padding(Theme.Spacing.large)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.Colors.background)
        #if !os(watchOS) && !os(tvOS)
        .toolbar { accountToolbar }
        #endif
        .refreshableIfAvailable {
            await refresh()
        }
        .task {
            await refresh()
        }
        .boothStatusLive(liveStore)
    }

    public func refresh() async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        async let meResult = capture { try await client.fetchMe() }
        async let storeRefresh: Void = liveStore.refreshNow()
        let meOutcome = await meResult
        await storeRefresh
        if let newMe = try? meOutcome.get() {
            profile = newMe
        } else if profile == nil {
            let reason = describe(error: meOutcome.failureOrNil)
            errorMessage = "Couldn't reach the operator: \(reason)"
        }
    }

    private func capture<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func describe(error: Error?) -> String {
        guard let error else { return "unknown error" }
        switch error {
        case OperatorError.unauthorized(let body):
            return "401 unauthorized (\(body.prefix(120)))"
        case OperatorError.httpError(let status, let body):
            return "HTTP \(status) (\(body.prefix(120)))"
        case OperatorError.transport(let inner):
            return "transport — \(inner.localizedDescription)"
        case OperatorError.unauthenticated:
            return "not signed in"
        default:
            return error.localizedDescription
        }
    }

    private var displayError: String? {
        errorMessage ?? liveStore.lastError
    }

    #if !os(watchOS) && !os(tvOS)
    /// Demoted account affordance: the signed-in identity and a sign-out
    /// (or exit-demo) action tucked into the toolbar so the booth content
    /// stays front-and-centre.
    @ToolbarContentBuilder
    private var accountToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let profile {
                    Section(profile.name) {
                        Text(profile.email)
                        if profile.isAdmin {
                            Label("Admin", systemImage: "checkmark.seal.fill")
                        }
                        if !profile.groups.isEmpty {
                            Text(profile.groups.joined(separator: " · "))
                        }
                    }
                }
                if config.isDemoMode {
                    Button {
                        config.disableDemoMode()
                    } label: {
                        Label("Exit Demo Mode", systemImage: "sparkles")
                    }
                } else {
                    Button(role: .destructive) {
                        Task { await auth.signOutRevokingNotifications() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } label: {
                Label(profile?.name ?? "Account", systemImage: "person.crop.circle")
            }
            .accessibilityLabel("Account")
        }
    }
    #endif

    private var overviewCard: some View {
        DashboardOverviewCard(
            status: currentStatus,
            stats: liveStore.stats,
            connection: liveStore.connection
        )
    }

    private var currentStatus: BoothStatus? {
        liveStore.status ?? liveStore.stats?.booth
    }

    @ViewBuilder
    private var secondaryCards: some View {
        let healthCard = SystemVitalsStrip(
            snapshot: liveStore.systemEnvelope?.snapshot,
            receivedAt: liveStore.systemEnvelope?.receivedAt,
            componentSources: liveStore.componentSources,
            boothId: liveStore.systemEnvelope?.boothId,
            presentation: .summary
        )
        #if !os(watchOS) && !os(tvOS)
        if liveStore.history.isEmpty {
            healthCard
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                    healthCard
                        .frame(minWidth: 280, maxWidth: .infinity)
                    DashboardActivityCard(items: liveStore.history.collapsingRepeats())
                        .frame(minWidth: 360, maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                    healthCard
                    DashboardActivityCard(items: liveStore.history.collapsingRepeats())
                }
            }
        }
        #else
        healthCard
        #endif
    }
}

private struct DashboardOverviewCard: View {
    let status: BoothStatus?
    let stats: StatsSummary?
    let connection: BoothStatusLiveStore.ConnectionState
    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                HStack {
                    SectionHeader(text: "Booth")
                    Spacer(minLength: Theme.Spacing.small)
                    DashboardConnectionBadge(connection: connection)
                }
                if let status {
                    statusRow(status, now: context.date)
                    if let error = status.lastError, !error.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Fonts.bodySmall)
                            .foregroundStyle(Theme.Colors.error)
                            .padding(Theme.Spacing.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.Colors.error.opacity(0.12))
                            }
                    }
                } else {
                    HStack(spacing: Theme.Spacing.small) {
                        if connection == .offline {
                            Image(systemName: "wifi.slash").foregroundStyle(Theme.Colors.error)
                        } else {
                            ProgressView()
                        }
                        Text(connection.dashboardEmptyStatusMessage)
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.vertical, Theme.Spacing.small)
                }
                Divider().background(Theme.Colors.textSecondary.opacity(0.2))
                metrics
            }
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardBackground()
    }

    private func statusRow(_ status: BoothStatus, now: Date) -> some View {
        let isOffline = boothStaleness(lastStatusAt: status.updatedAt, now: now).level == .offline
        let presentation = isOffline ? BoothStatePresentation.offline : status.state.dashboardPresentation
        let tint = isOffline ? Theme.Colors.error : status.state.dashboardTint
        let detail = isOffline ? "Waiting for fresh booth telemetry"
            : "\(presentation.name) for " + DurationFormatter.compactString(from: status.heldSince, to: now)
        return HStack(alignment: .center, spacing: Theme.Spacing.medium) {
            BoothStateIcon(symbol: presentation.symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(Theme.Fonts.bodyLarge.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                Text(detail)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.small)
            VStack(alignment: .trailing, spacing: 6) {
                BoothStalenessChip(lastStatusAt: status.updatedAt)
                RuntimeModeBadge(mode: status.runtimeMode)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var metrics: some View {
        if let stats {
            HStack(spacing: Theme.Spacing.small) {
                DashboardMetric(label: "Calls today", value: stats.calls.today, symbol: "phone.fill")
                DashboardMetric(
                    label: "Messages",
                    value: stats.messages.receivedToday,
                    symbol: "waveform"
                )
                DashboardMetric(
                    label: "To review",
                    value: stats.messages.badgeCount,
                    symbol: "tray.full.fill"
                )
            }
        } else {
            HStack(spacing: Theme.Spacing.small) {
                ProgressView().controlSize(.small)
                Text("Loading today's totals...")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}

private struct DashboardConnectionBadge: View {
    let connection: BoothStatusLiveStore.ConnectionState
    var body: some View {
        let presentation = badge
        return Label(presentation.label, systemImage: presentation.symbol)
            .font(Theme.Fonts.caption.weight(.semibold))
            .foregroundStyle(presentation.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background { Capsule().fill(presentation.tint.opacity(0.12)) }
            .accessibilityLabel(Text("Status connection: \(presentation.label)"))
    }
    private var badge: DashboardBadgePresentation {
        switch connection {
        case .connecting: return DashboardBadgePresentation("Connecting", "ellipsis", Theme.Colors.warning)
        case .live: return DashboardBadgePresentation("Live", "bolt.fill", Theme.Colors.success)
        case .polling:
            return DashboardBadgePresentation("Updating", "arrow.triangle.2.circlepath", Theme.Colors.info)
        case .offline: return DashboardBadgePresentation("Offline", "wifi.slash", Theme.Colors.error)
        }
    }
}

private struct DashboardBadgePresentation {
    let label, symbol: String
    let tint: Color
    init(_ label: String, _ symbol: String, _ tint: Color) {
        self.label = label
        self.symbol = symbol
        self.tint = tint
    }
}

private struct DashboardMetric: View {
    let label: String
    let value: Int
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: symbol)
                .font(Theme.Fonts.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value.formatted())
                .font(Theme.Fonts.headerLarge().monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Colors.textPrimary.opacity(0.06))
        }
        .accessibilityElement(children: .combine)
    }
}

#if !os(watchOS) && !os(tvOS)
private struct DashboardActivityCard: View {
    let items: [BoothStatus]
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionHeader(text: "Recent activity")
                    Text(summary)
                        .font(Theme.Fonts.bodyMedium.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Spacer(minLength: Theme.Spacing.small)
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.Colors.accent)
                        .frame(width: 7, height: 7)
                    Text("Call active")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            StatusHistoryChart(items: items)
                .frame(height: 62)
            if let first = items.first, let last = items.last {
                HStack {
                    Text(first.heldSince, format: .dateTime.hour().minute())
                    Spacer()
                    Text(last.updatedAt, format: .dateTime.hour().minute())
                }
                .font(Theme.Fonts.caption.monospacedDigit())
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardBackground()
    }
    private var summary: String {
        guard let first = items.first, let last = items.last else { return "No recent status yet" }
        let span = DurationFormatter.compactString(from: first.heldSince, to: last.updatedAt)
        let count = recentCallCount
        if count == 0 { return "Quiet across \(span)" }
        return "\(count) \(count == 1 ? "call" : "calls") across \(span)"
    }
    private var recentCallCount: Int {
        var wasActive = false
        return items.reduce(into: 0) { count, item in
            let isActive = item.state.isCallActive
            if isActive, !wasActive { count += 1 }
            wasActive = isActive
        }
    }
}

private struct StatusHistoryChart: View {
    let items: [BoothStatus]
    var body: some View {
        Chart(Array(items.enumerated()), id: \.offset) { index, item in
            if item.updatedAt > item.heldSince {
                RectangleMark(
                    xStart: .value("Started", item.heldSince),
                    xEnd: .value("Ended", item.updatedAt),
                    yStart: .value("Lane start", 0),
                    yEnd: .value("Lane end", 1)
                )
                .foregroundStyle(color(for: item.state))
            } else {
                PointMark(
                    x: .value("Transition", item.heldSince),
                    y: .value("Transition order", items.instantTransitionLane(at: index))
                )
                .symbolSize(42)
                .foregroundStyle(color(for: item.state))
                .zIndex(1)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .chartPlotStyle { plotArea in
            plotArea
                .background(Theme.Colors.textPrimary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityLabel(Text("Recent booth activity"))
    }

    private func color(for state: BoothState) -> Color {
        if state == .error { return Theme.Colors.error }
        if state.isCallActive { return Theme.Colors.accent }
        return Theme.Colors.textSecondary.opacity(0.16)
    }
}
#endif

private struct BoothStateIcon: View {
    let symbol: String
    let tint: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background {
                Circle().fill(tint.opacity(0.14))
            }
            .accessibilityHidden(true)
    }
}

private extension BoothState {
    var dashboardPresentation: BoothStatePresentation {
        switch self {
        case .idle: return BoothStatePresentation("Idle", "Ready for the next call", "phone.fill")
        case .dialTone: return BoothStatePresentation("Dial tone", "A caller is on the line", "phone.fill")
        case .dialing: return BoothStatePresentation("Dialing", "Dialing in progress", "circle.grid.3x3.fill")
        case .playingQuestion:
            return BoothStatePresentation("Playing question", "Playing a question", "speaker.wave.2.fill")
        case .beep: return BoothStatePresentation("Beep", "Waiting for the response", "waveform")
        case .recording: return BoothStatePresentation("Recording", "Recording a message", "mic.fill")
        case .uploading: return BoothStatePresentation("Uploading", "Saving the recording", "arrow.up.circle.fill")
        case .playingMessage: return BoothStatePresentation("Playing message", "Playing a message", "play.fill")
        case .playingInstructions:
            return BoothStatePresentation("Playing instructions", "Playing instructions", "text.bubble.fill")
        case .callUnavailable:
            return BoothStatePresentation("Call unavailable", "Call unavailable", "phone.down.fill")
        case .error: return BoothStatePresentation("Error", "Booth needs attention", "exclamationmark.triangle.fill")
        case .unknown(let value):
            return BoothStatePresentation(value, "Unknown booth state", "questionmark.circle.fill")
        }
    }

    var dashboardTint: Color {
        switch self {
        case .idle, .dialTone: return Theme.Colors.success
        case .error: return Theme.Colors.error
        case .callUnavailable: return Theme.Colors.warning
        case .unknown: return Theme.Colors.textSecondary
        default: return Theme.Colors.accent
        }
    }
}

private struct BoothStatePresentation {
    let name, title, symbol: String
    static let offline = BoothStatePresentation("Unavailable", "Booth status unavailable", "wifi.slash")
    init(_ name: String, _ title: String, _ symbol: String) {
        self.name = name
        self.title = title
        self.symbol = symbol
    }
}

private extension Result {
    var failureOrNil: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
