//
//  ThermalHistory.swift
//  TelephoneBoothOperatorMobile
//
//  Thermal time-series contract and pure chart-shaping helpers.
//

import Foundation

public enum ThermalMetricName {
    public static let piCPU = "booth_cpu_temperature_celsius"
    public static let routerBattery = "glinet_battery_temperature_celsius"
    public static let routerZone = "glinet_thermal_temperature_celsius"
}

public enum CurrentWeatherCondition: Codable, Sendable, Equatable, Hashable {
    case clearSky
    case mainlyClear
    case partlyCloudy
    case overcast
    case fog
    case rimeFog
    case drizzle
    case freezingDrizzle
    case rain
    case freezingRain
    case snowfall
    case snowGrains
    case rainShowers
    case snowShowers
    case thunderstorm
    case thunderstormWithHail
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .clearSky: return "clear_sky"
        case .mainlyClear: return "mainly_clear"
        case .partlyCloudy: return "partly_cloudy"
        case .overcast: return "overcast"
        case .fog: return "fog"
        case .rimeFog: return "rime_fog"
        case .drizzle: return "drizzle"
        case .freezingDrizzle: return "freezing_drizzle"
        case .rain: return "rain"
        case .freezingRain: return "freezing_rain"
        case .snowfall: return "snowfall"
        case .snowGrains: return "snow_grains"
        case .rainShowers: return "rain_showers"
        case .snowShowers: return "snow_showers"
        case .thunderstorm: return "thunderstorm"
        case .thunderstormWithHail: return "thunderstorm_with_hail"
        case .unknown(let value): return value
        }
    }

    // Keep every API contract value visible here so condition formatting and
    // Codable round-tripping remain explicit.
    // swiftlint:disable:next cyclomatic_complexity
    public init(rawValue: String) {
        switch rawValue {
        case "clear_sky": self = .clearSky
        case "mainly_clear": self = .mainlyClear
        case "partly_cloudy": self = .partlyCloudy
        case "overcast": self = .overcast
        case "fog": self = .fog
        case "rime_fog": self = .rimeFog
        case "drizzle": self = .drizzle
        case "freezing_drizzle": self = .freezingDrizzle
        case "rain": self = .rain
        case "freezing_rain": self = .freezingRain
        case "snowfall": self = .snowfall
        case "snow_grains": self = .snowGrains
        case "rain_showers": self = .rainShowers
        case "snow_showers": self = .snowShowers
        case "thunderstorm": self = .thunderstorm
        case "thunderstorm_with_hail": self = .thunderstormWithHail
        case "unknown": self = .unknown("unknown")
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

public struct CurrentWeather: Codable, Sendable, Equatable {
    public let boothId: String
    public let source: String
    public let temperatureCelsius: Double
    public let relativeHumidityPercent: Double
    public let cloudCoverPercent: Double
    public let condition: CurrentWeatherCondition
    public let observedAt: Date
    public let fetchedAt: Date

    public init(
        boothId: String,
        source: String,
        temperatureCelsius: Double,
        relativeHumidityPercent: Double,
        cloudCoverPercent: Double,
        condition: CurrentWeatherCondition,
        observedAt: Date,
        fetchedAt: Date
    ) {
        self.boothId = boothId
        self.source = source
        self.temperatureCelsius = temperatureCelsius
        self.relativeHumidityPercent = relativeHumidityPercent
        self.cloudCoverPercent = cloudCoverPercent
        self.condition = condition
        self.observedAt = observedAt
        self.fetchedAt = fetchedAt
    }

    public func freshnessLabel(now: Date = Date()) -> String {
        "Fetched \(Self.ageLabel(for: fetchedAt, now: now)) · "
            + "observed \(Self.ageLabel(for: observedAt, now: now))"
    }

    private static func ageLabel(for date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 0 {
            return "in \(durationLabel(seconds: -seconds))"
        }
        return seconds < 60 ? "just now" : "\(durationLabel(seconds: seconds)) ago"
    }

    private static func durationLabel(seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(1, minutes))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

public enum ThermalSeriesKind: Sendable, Equatable, Hashable {
    case piCPU
    case routerBattery
    case routerZone(String)
    case unsupported(String)

    public var displayName: String {
        switch self {
        case .piCPU:
            return "Pi CPU"
        case .routerBattery:
            return "Router battery"
        case .routerZone(let name):
            return name == "Thermal zone" ? "Router thermal zone" : "Router zone · \(name)"
        case .unsupported(let metric):
            return metric
        }
    }
}

public struct ThermalHistoryPoint: Codable, Sendable, Equatable {
    public let timestamp: Double
    public let value: Double

    public init(timestamp: Double, value: Double) {
        self.timestamp = timestamp
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeFlexibleDouble(forKey: .timestamp)
        value = try container.decodeFlexibleDouble(forKey: .value)
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case value
    }
}

public struct ThermalHistorySeries: Codable, Sendable, Equatable, Identifiable {
    public let metric: String
    public let labels: [String: String]
    public let points: [ThermalHistoryPoint]

    public init(
        metric: String,
        labels: [String: String] = [:],
        points: [ThermalHistoryPoint]
    ) {
        self.metric = metric
        self.labels = labels
        self.points = points
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metric = try container.decode(String.self, forKey: .metric)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        points = try container.decodeIfPresent([ThermalHistoryPoint].self, forKey: .points) ?? []
    }

    public var id: String {
        let labelKey = labels
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return labelKey.isEmpty ? metric : "\(metric)?\(labelKey)"
    }

    public var kind: ThermalSeriesKind {
        switch metric {
        case ThermalMetricName.piCPU:
            return .piCPU
        case ThermalMetricName.routerBattery:
            return .routerBattery
        case ThermalMetricName.routerZone:
            return .routerZone(Self.routerZoneName(labels: labels))
        default:
            return .unsupported(metric)
        }
    }

    public static func routerZoneName(labels: [String: String]) -> String {
        let typeName = firstNonEmptyLabel(
            in: labels,
            keys: ["type", "sensor", "display_name", "displayName"]
        )
        let zoneName = firstNonEmptyLabel(
            in: labels,
            keys: ["zone", "zone_name", "thermal_zone", "name", "path", "id"]
        )

        if let typeName, let zoneName,
           typeName.caseInsensitiveCompare(zoneName) != .orderedSame {
            return "\(typeName) · \(zoneName)"
        }
        return typeName ?? zoneName ?? "Thermal zone"
    }

    private static func firstNonEmptyLabel(
        in labels: [String: String],
        keys: [String]
    ) -> String? {
        keys.lazy.compactMap { key in
            guard let value = labels[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return nil
            }
            return value
        }
        .first
    }
}

public struct ThermalHistoryResponse: Codable, Sendable, Equatable {
    public let boothId: String
    public let source: SystemComponentSource
    public let from: Date
    public let end: Date
    public let stepSeconds: Int
    public let series: [ThermalHistorySeries]

    public init(
        boothId: String,
        source: SystemComponentSource,
        from: Date,
        end: Date,
        stepSeconds: Int,
        series: [ThermalHistorySeries]
    ) {
        self.boothId = boothId
        self.source = source
        self.from = from
        self.end = end
        self.stepSeconds = stepSeconds
        self.series = series
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        boothId = try container.decode(String.self, forKey: .boothId)
        source = try container.decode(SystemComponentSource.self, forKey: .source)
        from = try container.decode(Date.self, forKey: .from)
        end = try container.decode(Date.self, forKey: .end)
        stepSeconds = try container.decode(Int.self, forKey: .stepSeconds)
        series = try container.decodeIfPresent([ThermalHistorySeries].self, forKey: .series) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case boothId
        case source
        case from
        case end = "to"
        case stepSeconds
        case series
    }
}

public struct ThermalChartPoint: Sendable, Equatable, Identifiable {
    public let timestamp: Double
    public let date: Date
    public let value: Double

    public init(timestamp: Double, value: Double) {
        self.timestamp = timestamp
        self.date = Date(timeIntervalSince1970: timestamp)
        self.value = value
    }

    public var id: Double { timestamp }
}

public struct ThermalChartSeries: Sendable, Equatable, Identifiable {
    public let id: String
    public let metric: String
    public let labels: [String: String]
    public let kind: ThermalSeriesKind
    public let displayName: String
    public let points: [ThermalChartPoint]

    public init?(_ series: ThermalHistorySeries) {
        let kind = series.kind
        if case .unsupported = kind { return nil }
        self.id = series.id
        self.metric = series.metric
        self.labels = series.labels
        self.kind = kind
        self.displayName = kind.displayName
        self.points = Self.normalizedPoints(series.points)
    }

    private static func normalizedPoints(
        _ points: [ThermalHistoryPoint]
    ) -> [ThermalChartPoint] {
        var valuesByTimestamp: [Double: Double] = [:]
        for point in points where point.timestamp.isFinite && point.value.isFinite {
            valuesByTimestamp[point.timestamp] = point.value
        }
        return valuesByTimestamp
            .map { ThermalChartPoint(timestamp: $0.key, value: $0.value) }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

public struct ThermalChartData: Sendable, Equatable {
    public let series: [ThermalChartSeries]
    public let piCPU: [ThermalChartSeries]
    public let routerBattery: [ThermalChartSeries]
    public let routerZones: [ThermalChartSeries]

    public init(history: ThermalHistoryResponse) {
        self.init(series: history.series)
    }

    public init(series historySeries: [ThermalHistorySeries]) {
        let shaped = historySeries
            .compactMap(ThermalChartSeries.init)
            .sorted(by: Self.isOrderedBefore)
        series = shaped
        piCPU = shaped.filter {
            if case .piCPU = $0.kind { return true }
            return false
        }
        routerBattery = shaped.filter {
            if case .routerBattery = $0.kind { return true }
            return false
        }
        routerZones = shaped.filter {
            if case .routerZone = $0.kind { return true }
            return false
        }
    }

    private static func isOrderedBefore(
        _ lhs: ThermalChartSeries,
        _ rhs: ThermalChartSeries
    ) -> Bool {
        let lhsRank = sortRank(lhs.kind)
        let rhsRank = sortRank(rhs.kind)
        if lhsRank != rhsRank { return lhsRank < rhsRank }

        let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id < rhs.id
    }

    private static func sortRank(_ kind: ThermalSeriesKind) -> Int {
        switch kind {
        case .piCPU: return 0
        case .routerBattery: return 1
        case .routerZone: return 2
        case .unsupported: return 3
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDouble(forKey key: Key) throws -> Double {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decode(String.self, forKey: key),
           let number = Double(value) {
            return number
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Expected a numeric value"
        )
    }
}
