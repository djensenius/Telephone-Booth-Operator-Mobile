//
//  OperatorClient+Metrics.swift
//  TelephoneBoothOperatorMobile
//
//  Advanced-metrics endpoints: custom-range stats overviews and per-operator
//  saved metric filters (`/v1/stats/filters`).
//

import Foundation

public extension OperatorClient {
    /// `GET /v1/stats/overview` for an arbitrary selection — a preset window
    /// or a custom `start`/`end` range (with `end=now` support). Custom
    /// ranges are computed fresh server-side (presets are cached for 30s).
    func fetchStatsOverview(selection: StatsRangeSelection) async throws -> StatsOverview {
        if await usesDemoData { return DemoData.statsOverview(selection: selection) }
        return try await get("/v1/stats/overview", query: selection.queryItems)
    }

    /// `GET /v1/stats/filters` — the current operator's saved metric filters.
    /// The API wraps the collection as `{ "items": [...] }`, so decode the
    /// envelope and return its contents.
    func fetchMetricFilters() async throws -> [MetricFilter] {
        if await usesDemoData { return DemoData.metricFilters }
        let response: MetricFilterList = try await get("/v1/stats/filters")
        return response.items
    }

    /// `POST /v1/stats/filters` — create a saved metric filter.
    func createMetricFilter(_ input: MetricFilterInput) async throws -> MetricFilter {
        if await usesDemoData {
            return MetricFilter(
                id: UUID().uuidString,
                name: input.name,
                window: input.window,
                start: input.start,
                end: input.end,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
        return try await postJSON("/v1/stats/filters", body: input)
    }

    /// `PUT /v1/stats/filters/{id}` — rename or re-scope a saved filter.
    func updateMetricFilter(id: String, input: MetricFilterInput) async throws -> MetricFilter {
        if await usesDemoData {
            return MetricFilter(
                id: id,
                name: input.name,
                window: input.window,
                start: input.start,
                end: input.end,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
        return try await putJSON("/v1/stats/filters/\(id)", body: input)
    }

    /// `DELETE /v1/stats/filters/{id}` — remove a saved filter.
    func deleteMetricFilter(id: String) async throws {
        if await usesDemoData { return }
        try await delete("/v1/stats/filters/\(id)")
    }
}

/// Envelope for `GET /v1/stats/filters`, which returns `{ "items": [...] }`.
private struct MetricFilterList: Decodable {
    let items: [MetricFilter]
}
