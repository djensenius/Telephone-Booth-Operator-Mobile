//
//  SharedComponents.swift
//  TelephoneBoothOperatorMobile
//
//  Small SwiftUI primitives reused across Status, Sessions, System, and
//  later feature surfaces. Keeping them in one place prevents implicit
//  coupling between feature folders.
//

import SwiftUI
#if canImport(Charts)
import Charts
#endif

private struct AutomaticRefreshEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var automaticRefreshEnabled: Bool {
        get { self[AutomaticRefreshEnabledKey.self] }
        set { self[AutomaticRefreshEnabledKey.self] = newValue }
    }
}

/// Uppercased section caption used at the top of each dashboard card.
public struct SectionHeader: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .font(Theme.Fonts.caption.weight(.semibold))
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

/// Label / value pair rendered as a key/value row.
public struct StatRow: View {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack {
            Text(label)
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(value)
                .font(Theme.Fonts.bodyMedium.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }
}

public enum BannerKind {
    case error, info

    public var color: Color {
        switch self {
        case .error: return Theme.Colors.error
        case .info: return Theme.Colors.info
        }
    }

    public var icon: String {
        switch self {
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

/// Compact inline banner for surface-level errors and notices.
public struct BannerView: View {
    public let message: String
    public let kind: BannerKind

    public init(message: String, kind: BannerKind) {
        self.message = message
        self.kind = kind
    }

    public var body: some View {
        Label(message, systemImage: kind.icon)
            .foregroundStyle(kind.color)
            .font(Theme.Fonts.bodySmall)
            .padding(Theme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardBackground()
    }
}

public extension View {
    func automaticRefreshEnabled(_ enabled: Bool) -> some View {
        environment(\.automaticRefreshEnabled, enabled)
    }

    /// Repeats a refresh while this view is visible and the app is active.
    /// Changing `id` restarts the loop.
    func autoRefresh<ID: Equatable>(
        id: ID,
        every interval: Duration = .seconds(30),
        immediately: Bool = true,
        action: @escaping @MainActor @Sendable () async -> Void
    ) -> some View {
        modifier(
            AutoRefreshModifier(
                id: id,
                interval: interval,
                immediately: immediately,
                action: action
            )
        )
    }

    func autoRefresh(
        every interval: Duration = .seconds(30),
        immediately: Bool = true,
        action: @escaping @MainActor @Sendable () async -> Void
    ) -> some View {
        autoRefresh(id: false, every: interval, immediately: immediately, action: action)
    }

    /// `.refreshable` is unavailable on tvOS. Apply it where supported,
    /// no-op elsewhere.
    @ViewBuilder
    func refreshableIfAvailable(_ action: @escaping @Sendable () async -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        self.refreshable(action: action)
        #endif
    }

    /// `.textSelection(.enabled)` is unavailable on tvOS and watchOS. Apply it
    /// where supported, no-op elsewhere.
    @ViewBuilder
    func textSelectionEnabledIfAvailable() -> some View {
        #if os(tvOS) || os(watchOS)
        self
        #else
        self.textSelection(.enabled)
        #endif
    }

    /// List style for the operator's content lists. macOS uses the native
    /// inset list (clean rows, system selection, no Catppuccin surface
    /// tinting); every other platform keeps the booth-flavoured plain list.
    @ViewBuilder
    func operatorListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.inset)
        #else
        self.listStyle(.plain)
        #endif
    }

    /// Row background for the operator's content rows. On macOS we let the
    /// inset list draw its native row background; elsewhere we tint rows with
    /// the Catppuccin secondary surface.
    @ViewBuilder
    func operatorListRowBackground() -> some View {
        #if os(macOS)
        self
        #else
        self.listRowBackground(Theme.Colors.secondaryBackground)
        #endif
    }
}

private struct AutoRefreshModifier<ID: Equatable>: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.automaticRefreshEnabled) private var automaticRefreshEnabled
    @State private var lastDelayedID: ID?

    let id: ID
    let interval: Duration
    let immediately: Bool
    let action: @MainActor @Sendable () async -> Void

    func body(content: Content) -> some View {
        let shouldRefresh = automaticRefreshEnabled && scenePhase != .background
        content.task(
            id: AutoRefreshTaskID(
                id: id,
                shouldRefresh: shouldRefresh,
                immediately: immediately
            )
        ) {
            guard shouldRefresh else { return }
            if !immediately, lastDelayedID != id {
                lastDelayedID = id
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
            while !Task.isCancelled {
                await action()
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }
}

private struct AutoRefreshTaskID<ID: Equatable>: Equatable {
    let id: ID
    let shouldRefresh: Bool
    let immediately: Bool
}

struct ReloadedPages<Item> {
    let items: [Item]
    let nextCursor: String?
    let pageCount: Int
}

@MainActor
func reloadLoadedPages<Item>(
    pageCount: Int,
    isCurrent: @MainActor () -> Bool,
    fetchPage: @MainActor (String?) async throws -> (items: [Item], nextCursor: String?)
) async throws -> ReloadedPages<Item> {
    let requestedPageCount = max(1, pageCount)
    var items: [Item] = []
    var nextCursor: String?
    var fetchedPageCount = 0

    repeat {
        guard isCurrent() else { throw CancellationError() }
        try Task.checkCancellation()
        let page = try await fetchPage(nextCursor)
        items.append(contentsOf: page.items)
        nextCursor = page.nextCursor
        fetchedPageCount += 1
    } while fetchedPageCount < requestedPageCount && nextCursor != nil

    return ReloadedPages(
        items: items,
        nextCursor: nextCursor,
        pageCount: fetchedPageCount
    )
}

/// Native trailing placement for list filter controls: the window toolbar's
/// primary action on macOS, an overflow secondary action elsewhere.
#if !os(watchOS) && !os(tvOS)
public var operatorFilterPlacement: ToolbarItemPlacement {
    #if os(macOS)
    .primaryAction
    #else
    .secondaryAction
    #endif
}
#endif

// MARK: - Booth staleness chip

/// Severity levels matching the operator web `BoothStatusBadge`
/// thresholds (fresh < 60 s, warning 60 s – 5 min, offline > 5 min).
public enum BoothStalenessLevel: Sendable, Equatable {
    case fresh
    case warning
    case offline
}

public enum BoothStalenessThresholds {
    public static let warningSeconds: TimeInterval = 60
    public static let offlineSeconds: TimeInterval = 300
}

extension BoothStatusLiveStore.ConnectionState {
    var dashboardEmptyStatusMessage: String {
        switch self {
        case .connecting: return "Connecting to the booth..."
        case .live, .polling: return "Waiting for booth status..."
        case .offline: return "Booth status unavailable"
        }
    }

}

/// Pure function for unit testing — given a `lastStatusAt` and the
/// current clock, returns the staleness level and a short label
/// ("Last seen 3m ago" / "Booth offline") or nil when fresh.
public func boothStaleness(
    lastStatusAt: Date?,
    now: Date = Date()
) -> (level: BoothStalenessLevel, label: String?) {
    guard let last = lastStatusAt else { return (.fresh, nil) }
    let elapsed = now.timeIntervalSince(last)
    if elapsed < BoothStalenessThresholds.warningSeconds {
        return (.fresh, nil)
    }
    if elapsed < BoothStalenessThresholds.offlineSeconds {
        let mins = max(1, Int((elapsed / 60).rounded()))
        return (.warning, "Last seen \(mins)m ago")
    }
    return (.offline, "Booth offline")
}

/// Small chip displayed next to the booth state badge when the operator
/// hasn't seen a status update in over a minute. Auto-ticks every 10 s
/// while visible (via `TimelineView`).
public struct BoothStalenessChip: View {
    public let lastStatusAt: Date?

    public init(lastStatusAt: Date?) {
        self.lastStatusAt = lastStatusAt
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let staleness = boothStaleness(lastStatusAt: lastStatusAt, now: context.date)
            if staleness.level != .fresh, let label = staleness.label {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: staleness.level))
                        .frame(width: 8, height: 8)
                    Text(label)
                        .font(Theme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(color(for: staleness.level))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    Capsule().fill(color(for: staleness.level).opacity(0.15))
                }
                .accessibilityLabel(Text(label))
            }
        }
    }

    private func color(for level: BoothStalenessLevel) -> Color {
        switch level {
        case .fresh: return Theme.Colors.success
        case .warning: return Theme.Colors.warning
        case .offline: return Theme.Colors.error
        }
    }
}

#if !os(watchOS) && !os(tvOS)
struct DashboardCallsTodayCard: View {
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
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionHeader(text: "Pickups today")
                        Text(summary(for: series))
                            .font(Theme.Fonts.bodyMedium.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Spacer(minLength: Theme.Spacing.small)
                    Label("Cumulative", systemImage: "chart.line.uptrend.xyaxis")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if !isLoaded {
                    ProgressView("Loading pickups...")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 112)
                } else if series.total == 0 {
                    Text("No pickups since midnight")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 112)
                } else {
                    CallsTodayChart(series: series)
                        .frame(height: 128)
                }
            }
            .padding(Theme.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardBackground()
        }
    }

    private func summary(for series: CallsTodaySeries) -> String {
        "\(series.total) \(series.total == 1 ? "pickup" : "pickups") since midnight"
    }
}

private struct CallsTodayChart: View {
    let series: CallsTodaySeries

    var body: some View {
        Chart {
            ForEach(series.points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Pickups", point.count)
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(Theme.Colors.accent)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            if let endpoint = series.points.last {
                PointMark(
                    x: .value("Time", endpoint.date),
                    y: .value("Pickups", endpoint.count)
                )
                .foregroundStyle(Theme.Colors.accent)
                .symbolSize(54)
                .annotation(position: .topLeading) {
                    Text("\(series.total)")
                        .font(Theme.Fonts.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .chartXScale(domain: chartDomain)
        .chartYScale(domain: 0...max(1, series.total + 1))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.08))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute())
                            .font(Theme.Fonts.caption.monospacedDigit())
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: series.yAxisValues) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.1))
                AxisValueLabel {
                    if let count = value.as(Int.self) {
                        Text("\(count)")
                            .font(Theme.Fonts.caption.monospacedDigit())
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(Theme.Colors.textPrimary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityLabel(Text("Cumulative pickups today"))
        .accessibilityValue(
            Text("\(series.total) \(series.total == 1 ? "pickup" : "pickups") since midnight")
        )
    }

    private var chartDomain: ClosedRange<Date> {
        series.chartDomain
            ?? (series.dayStartedAt...series.dayStartedAt.addingTimeInterval(60))
    }
}
#endif
