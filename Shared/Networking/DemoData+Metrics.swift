//
//  DemoData+Metrics.swift
//  TelephoneBoothOperatorMobile
//
//  Demo fixtures for the advanced-metrics surfaces (saved filters and custom
//  ranges). Kept out of `Shared/Models/DemoData.swift` because it references
//  `MetricFilter` / `StatsRangeSelection`, which are app-only types (the
//  WidgetKit target compiles `Shared/Models` but not `Shared/Networking`).
//

import Foundation

public extension DemoData {
    static let metricFilters: [MetricFilter] = [
        MetricFilter(
            id: "11111111-2222-3333-4444-555555555555",
            name: "Opening weekend",
            window: nil,
            start: now.addingTimeInterval(-14 * 24 * 60 * 60),
            end: now.addingTimeInterval(-12 * 24 * 60 * 60),
            createdAt: now.addingTimeInterval(-13 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-13 * 24 * 60 * 60)
        ),
        MetricFilter(
            id: "66666666-7777-8888-9999-000000000000",
            name: "Last 30 days",
            window: .last30d,
            start: nil,
            end: nil,
            createdAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-2 * 24 * 60 * 60)
        )
    ]

    static func statsOverview(selection: StatsRangeSelection) -> StatsOverview {
        switch selection {
        case .window(let window):
            return statsOverview(window: window)
        case .custom(let start, _, let end):
            let base = statsOverview(window: .last7d)
            return StatsOverview(
                window: .unknown("custom"),
                rangeStart: start ?? base.rangeStart,
                rangeEnd: end ?? now,
                generatedAt: base.generatedAt,
                timezone: base.timezone,
                calls: base.calls,
                messages: base.messages,
                playback: base.playback,
                pickupsHangups: base.pickupsHangups,
                uploads: base.uploads,
                topQuestions: base.topQuestions,
                hourly: base.hourly,
                busiest: base.busiest,
                lastActivityAt: base.lastActivityAt,
                boothBreakdown: base.boothBreakdown
            )
        }
    }
}
