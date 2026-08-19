//
//  OperatorClient+Metrics.swift
//  TelephoneBoothOperatorMobile
//
//  Advanced-metrics endpoints: custom-range stats overviews and per-operator
//  saved metric filters (`/v1/stats/filters`).
//

import Foundation
import os

private let metricsLogger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "OperatorClient.Metrics"
)

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
        let overview: StatsOverview = try await get("/v1/stats/overview", query: query)
        do {
            return try await recoveringDialedDigits(
                in: overview,
                installationScope: installationScope
            )
        } catch let error as OperatorError {
            if Task.isCancelled || error.isCancellation {
                throw CancellationError()
            }
            metricsLogger.warning(
                "Dialed-digit recovery unavailable: \(String(describing: type(of: error)), privacy: .public)"
            )
            return overview
        }
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

private struct DialedDigitEventPage: Decodable, Sendable {
    let items: [DialedDigitEvent]
    let nextCursor: String?
}

private struct DialedDigitEvent: Decodable, Sendable {
    let digit: Int?

    private enum CodingKeys: String, CodingKey {
        case payload
    }

    private enum PayloadCodingKeys: String, CodingKey {
        case digit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let payload = try? container.nestedContainer(
            keyedBy: PayloadCodingKeys.self,
            forKey: .payload
        ) else {
            digit = nil
            return
        }
        digit = try? payload.decode(Int.self, forKey: .digit)
    }
}

private enum DialedDigitEventError: LocalizedError {
    case repeatedCursor(String)

    var errorDescription: String? {
        switch self {
        case .repeatedCursor(let cursor):
            return "Digit event pagination repeated cursor \(cursor)."
        }
    }
}

private extension OperatorClient {
    /// Some operator versions aggregate this field from `CallSession.digitsDialed`,
    /// while booth clients report the actual values as `digit_dialed` events.
    /// Recover only an empty aggregate so a corrected server remains authoritative.
    func recoveringDialedDigits(
        in overview: StatsOverview,
        installationScope: InstallationScope
    ) async throws -> StatsOverview {
        let hasCalls = overview.pickupsHangups.pickups > 0 || overview.pickupsHangups.hangups > 0
        let hasReportedDigits = overview.pickupsHangups.digitsDialed.values.contains { $0 > 0 }
        guard hasCalls, !hasReportedDigits else { return overview }

        let digitsDialed = try await fetchDialedDigitEventCounts(
            since: overview.rangeStart,
            until: overview.rangeEnd,
            installationScope: installationScope
        )
        guard digitsDialed.values.contains(where: { $0 > 0 }) else { return overview }
        return overview.replacingDialedDigits(with: digitsDialed)
    }

    func fetchDialedDigitEventCounts(
        since: Date?,
        until: Date,
        installationScope: InstallationScope
    ) async throws -> [String: Int] {
        var counts = Dictionary(uniqueKeysWithValues: (0...9).map { (String($0), 0) })
        var cursor: String?
        var seenCursors: Set<String> = []

        repeat {
            var query = [
                URLQueryItem(name: "type", value: BoothEventType.digitDialed.rawValue),
                URLQueryItem(name: "until", value: OperatorJSON.iso8601String(from: until)),
                URLQueryItem(name: "limit", value: "500")
            ]
            if let since {
                query.append(
                    URLQueryItem(name: "since", value: OperatorJSON.iso8601String(from: since))
                )
            }
            if let installationID = installationScope.queryValue {
                query.append(URLQueryItem(name: "installationId", value: installationID))
            }
            if let cursor {
                query.append(URLQueryItem(name: "cursor", value: cursor))
            }

            let page: DialedDigitEventPage = try await get("/v1/events", query: query)
            for event in page.items {
                guard let digit = event.digit, (0...9).contains(digit) else { continue }
                counts[String(digit), default: 0] += 1
            }

            cursor = page.nextCursor
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw OperatorError.decoding(DialedDigitEventError.repeatedCursor(cursor))
            }
        } while cursor != nil

        return counts
    }
}

private extension OperatorError {
    var isCancellation: Bool {
        guard case .transport(let error) = self else { return false }
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }
}

private extension StatsOverview {
    func replacingDialedDigits(with digitsDialed: [String: Int]) -> StatsOverview {
        StatsOverview(
            window: window,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            generatedAt: generatedAt,
            timezone: timezone,
            calls: calls,
            messages: messages,
            playback: playback,
            pickupsHangups: PickupsHangups(
                pickups: pickupsHangups.pickups,
                hangups: pickupsHangups.hangups,
                digitsDialed: digitsDialed
            ),
            uploads: uploads,
            topQuestions: topQuestions,
            hourly: hourly,
            busiest: busiest,
            lastActivityAt: lastActivityAt,
            boothBreakdown: boothBreakdown
        )
    }
}
