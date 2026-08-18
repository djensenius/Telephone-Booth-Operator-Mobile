//
//  OperatorClient+Thermals.swift
//  TelephoneBoothOperatorMobile
//
//  Current component telemetry and historical thermal-series endpoints.
//

import Foundation

struct ThermalEndpointRequest {
    let path: String
    let queryItems: [URLQueryItem]

    func url(relativeTo baseURL: URL) throws -> URL {
        let base = baseURL.appendingPathComponent(String(path.dropFirst()))
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw OperatorError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw OperatorError.invalidURL }
        return url
    }
}

enum ThermalEndpoint {
    static let currentComponents = ThermalEndpointRequest(
        path: "/v1/system/components/current",
        queryItems: []
    )

    static func currentWeather(boothId: String) throws -> ThermalEndpointRequest {
        let normalizedBoothId = boothId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBoothId.isEmpty else { throw OperatorError.invalidURL }
        return ThermalEndpointRequest(
            path: "/v1/system/weather/current",
            queryItems: [URLQueryItem(name: "boothId", value: normalizedBoothId)]
        )
    }

    static func history(query: ThermalHistoryQuery) throws -> ThermalEndpointRequest {
        guard !query.boothId.isEmpty else { throw OperatorError.invalidURL }
        return ThermalEndpointRequest(
            path: "/v1/system/thermals/history",
            queryItems: query.queryItems
        )
    }
}

public struct ThermalHistoryQuery: Sendable, Hashable {
    public static let minimumStepSeconds = 15

    public let boothId: String
    public let componentId: String?
    public let from: Date
    public let end: Date
    public let stepSeconds: Int

    public init(
        boothId: String,
        componentId: String? = nil,
        from: Date,
        end: Date,
        stepSeconds: Int
    ) {
        self.boothId = boothId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedComponentId = componentId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.componentId = trimmedComponentId?.isEmpty == false ? trimmedComponentId : nil
        self.from = min(from, end)
        self.end = max(from, end)
        self.stepSeconds = max(Self.minimumStepSeconds, stepSeconds)
    }

    public var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "boothId", value: boothId),
            URLQueryItem(name: "from", value: OperatorJSON.iso8601String(from: from)),
            URLQueryItem(name: "to", value: OperatorJSON.iso8601String(from: end)),
            URLQueryItem(name: "stepSeconds", value: String(stepSeconds))
        ]
        if let componentId {
            items.insert(URLQueryItem(name: "componentId", value: componentId), at: 1)
        }
        return items
    }
}

public enum ThermalRangePreset: String, CaseIterable, Sendable, Hashable, Identifiable {
    case last6Hours = "6h"
    case last24Hours = "24h"
    case last7Days = "7d"
    case last30Days = "30d"

    public static let `default`: ThermalRangePreset = .last24Hours

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .last6Hours: return "Last 6 hours"
        case .last24Hours: return "Last 24 hours"
        case .last7Days: return "Last 7 days"
        case .last30Days: return "Last 30 days"
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .last6Hours: return 6 * 60 * 60
        case .last24Hours: return 24 * 60 * 60
        case .last7Days: return 7 * 24 * 60 * 60
        case .last30Days: return 30 * 24 * 60 * 60
        }
    }

    public var stepSeconds: Int {
        switch self {
        case .last6Hours: return 60
        case .last24Hours: return 5 * 60
        case .last7Days: return 30 * 60
        case .last30Days: return 2 * 60 * 60
        }
    }

    public func query(
        boothId: String,
        componentId: String? = nil,
        now: Date = Date()
    ) -> ThermalHistoryQuery {
        ThermalHistoryQuery(
            boothId: boothId,
            componentId: componentId,
            from: now.addingTimeInterval(-duration),
            end: now,
            stepSeconds: stepSeconds
        )
    }
}

public extension OperatorClient {
    /// `GET /v1/system/components/current` — latest snapshots for component
    /// telemetry sources across the fleet.
    func fetchCurrentSystemComponents() async throws -> [SystemComponentCurrentEnvelope] {
        if await usesDemoData { return DemoData.systemComponentSources }
        let endpoint = ThermalEndpoint.currentComponents
        do {
            let response: SystemComponentCurrentList = try await get(endpoint.path)
            return response.items.sorted(by: Self.componentSourceOrder)
        } catch let OperatorError.httpError(status, _) where status == 404 {
            return []
        }
    }

    /// `GET /v1/system/thermals/history` for a normalized booth/range query.
    func fetchThermalHistory(
        query: ThermalHistoryQuery
    ) async throws -> ThermalHistoryResponse {
        let endpoint = try ThermalEndpoint.history(query: query)
        if await usesDemoData { return DemoData.thermalHistory(query: query) }
        return try await get(
            endpoint.path,
            query: endpoint.queryItems
        )
    }

    /// Convenience overload for callers that do not need to retain a query.
    func fetchThermalHistory(
        boothId: String,
        from: Date,
        end: Date,
        stepSeconds: Int
    ) async throws -> ThermalHistoryResponse {
        try await fetchThermalHistory(
            query: ThermalHistoryQuery(
                boothId: boothId,
                from: from,
                end: end,
                stepSeconds: stepSeconds
            )
        )
    }

    /// `GET /v1/system/weather/current?boothId=…` — latest outdoor weather
    /// reading for one booth. A 404 means the operator has no current weather
    /// reading, rather than a failed thermal request.
    func fetchCurrentWeather(boothId: String) async throws -> CurrentWeather? {
        let endpoint = try ThermalEndpoint.currentWeather(boothId: boothId)
        if await usesDemoData {
            return DemoData.currentWeather(boothId: boothId)
        }
        do {
            return try await get(endpoint.path, query: endpoint.queryItems)
        } catch let OperatorError.httpError(status, _) where status == 404 {
            return nil
        }
    }

    private static func componentSourceOrder(
        _ lhs: SystemComponentCurrentEnvelope,
        _ rhs: SystemComponentCurrentEnvelope
    ) -> Bool {
        let boothOrder = lhs.source.boothId.localizedCaseInsensitiveCompare(rhs.source.boothId)
        if boothOrder != .orderedSame { return boothOrder == .orderedAscending }
        let nameOrder = lhs.source.effectiveDisplayName.localizedCaseInsensitiveCompare(
            rhs.source.effectiveDisplayName
        )
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id < rhs.id
    }
}
