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
    func fetchStatsOverview(
        selection: StatsRangeSelection,
        installationScope: InstallationScope = .current
    ) async throws -> StatsOverview {
        if await usesDemoData { return DemoData.statsOverview(selection: selection) }
        var query = selection.queryItems
        if let installationID = installationScope.queryValue {
            query.append(URLQueryItem(name: "installationId", value: installationID))
        }
        return try await get("/v1/stats/overview", query: query)
    }

    /// `GET /v1/installations` — all eras, newest first, for the stats scope
    /// selector and administrator installation settings.
    func fetchInstallations() async throws -> [Installation] {
        if await usesDemoData { return DemoData.installations }
        let response: InstallationList = try await get("/v1/installations")
        return response.items
    }

    /// `GET /v1/installations/current` returns 404 between installations.
    func fetchCurrentInstallation() async throws -> Installation? {
        if await usesDemoData { return DemoData.installations.first(where: \.isActive) }
        do {
            let installation: Installation = try await get("/v1/installations/current")
            return installation
        } catch let OperatorError.httpError(status, _) where status == 404 {
            return nil
        }
    }

    /// `PATCH /v1/installations/{id}` lets administrators set the default
    /// source language used by automatically claimed transcription work.
    func updateInstallationLanguage(
        id: String,
        defaultTranscriptionLanguage: String?
    ) async throws -> Installation {
        if await usesDemoData {
            guard let installation = DemoData.installations.first(where: { $0.id == id }) else {
                throw OperatorError.httpError(status: 404, body: "not_found")
            }
            return Installation(
                id: installation.id,
                name: installation.name,
                notes: installation.notes,
                location: installation.location,
                defaultTranscriptionLanguage: defaultTranscriptionLanguage,
                startedAt: installation.startedAt,
                endedAt: installation.endedAt,
                endedById: installation.endedById,
                summary: installation.summary,
                createdAt: installation.createdAt,
                isActive: installation.isActive
            )
        }
        return try await patchJSON(
            "/v1/installations/\(id)",
            body: InstallationUpdateRequest(
                defaultTranscriptionLanguage: defaultTranscriptionLanguage
            )
        )
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
