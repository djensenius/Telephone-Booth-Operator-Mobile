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
    static let systemComponentSources: [SystemComponentCurrentEnvelope] = [
        SystemComponentCurrentEnvelope(
            source: SystemComponentSource(
                boothId: boothId,
                componentId: "glinet-router",
                displayName: "Booth router",
                kind: "router",
                prometheusJob: "glinet",
                prometheusInstance: "booth-router"
            ),
            latestSnapshot: SystemComponentSnapshot(
                receivedAt: now.addingTimeInterval(-20),
                battery: .init(temperatureCelsius: 42.8),
                thermalZones: [
                    .init(name: "CPU", temperatureCelsius: 51.4),
                    .init(name: "Wi-Fi", temperatureCelsius: 47.9)
                ]
            )
        )
    ]

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

    static func thermalHistory(query: ThermalHistoryQuery) -> ThermalHistoryResponse {
        let duration = max(1, query.end.timeIntervalSince(query.from))
        let requestedCount = Int(duration / Double(query.stepSeconds)) + 1
        let sampleCount = min(240, max(2, requestedCount))
        let sampleInterval = duration / Double(sampleCount - 1)

        func points(base: Double, amplitude: Double, phase: Double) -> [ThermalHistoryPoint] {
            (0..<sampleCount).map { index in
                let progress = Double(index) / Double(sampleCount - 1)
                let wave = sin(progress * .pi * 4 + phase)
                let timestamp = query.from.timeIntervalSince1970 + Double(index) * sampleInterval
                return ThermalHistoryPoint(
                    timestamp: timestamp,
                    value: base + amplitude * wave
                )
            }
        }

        let source = systemComponentSources[0].source
        return ThermalHistoryResponse(
            boothId: query.boothId,
            source: source,
            from: query.from,
            end: query.end,
            stepSeconds: query.stepSeconds,
            series: [
                ThermalHistorySeries(
                    metric: ThermalMetricName.piCPU,
                    points: points(base: 49, amplitude: 4.5, phase: 0)
                ),
                ThermalHistorySeries(
                    metric: ThermalMetricName.routerBattery,
                    points: points(base: 42, amplitude: 1.8, phase: 0.6)
                ),
                ThermalHistorySeries(
                    metric: ThermalMetricName.routerZone,
                    labels: ["type": "CPU", "zone": "thermal_zone0"],
                    points: points(base: 52, amplitude: 3.8, phase: 1.1)
                ),
                ThermalHistorySeries(
                    metric: ThermalMetricName.routerZone,
                    labels: ["type": "Wi-Fi", "zone": "thermal_zone1"],
                    points: points(base: 47, amplitude: 2.3, phase: 1.8)
                )
            ]
        )
    }
}
