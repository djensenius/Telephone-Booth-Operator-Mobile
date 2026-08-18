//
//  SystemComponentSnapshot.swift
//  TelephoneBoothOperatorMobile
//
//  Current component-source telemetry returned by
//  `GET /v1/system/components/current`.
//

import Foundation

public struct SystemComponentSource: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let boothId: String
    public let componentId: String
    public let displayName: String
    public let kind: String
    public let prometheusJob: String
    public let prometheusInstance: String

    public init(
        boothId: String,
        componentId: String,
        displayName: String,
        kind: String,
        prometheusJob: String,
        prometheusInstance: String
    ) {
        self.boothId = boothId
        self.componentId = componentId
        self.displayName = displayName
        self.kind = kind
        self.prometheusJob = prometheusJob
        self.prometheusInstance = prometheusInstance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        boothId = try container.decode(String.self, forKey: .boothId)
        componentId = try container.decode(String.self, forKey: .componentId)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? componentId
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "unknown"
        prometheusJob = try container.decodeIfPresent(String.self, forKey: .prometheusJob) ?? ""
        prometheusInstance = try container.decodeIfPresent(
            String.self,
            forKey: .prometheusInstance
        ) ?? ""
    }

    public var id: String {
        let componentKey = componentId.isEmpty ? prometheusInstance : componentId
        return "\(boothId)::\(componentKey)"
    }

    public var effectiveDisplayName: String {
        if !displayName.isEmpty { return displayName }
        if !componentId.isEmpty { return componentId }
        return boothId
    }

    public var isRouter: Bool {
        let searchable = [
            kind,
            displayName,
            componentId,
            prometheusJob
        ]
        .joined(separator: " ")
        .lowercased()
        return searchable.contains("router") || searchable.contains("glinet")
    }

    private enum CodingKeys: String, CodingKey {
        case boothId
        case componentId
        case displayName
        case kind
        case prometheusJob
        case prometheusInstance
    }
}

public struct SystemComponentBattery: Codable, Sendable, Equatable {
    public let temperatureCelsius: Double?

    public init(temperatureCelsius: Double? = nil) {
        self.temperatureCelsius = temperatureCelsius
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        temperatureCelsius = container.flexibleDouble(forKey: .temperatureCelsius)
    }

    private enum CodingKeys: String, CodingKey {
        case temperatureCelsius
    }
}

public struct SystemComponentThermalZone: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let name: String
    public let temperatureCelsius: Double?

    public init(name: String, temperatureCelsius: Double? = nil) {
        self.name = name
        self.temperatureCelsius = temperatureCelsius
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = Self.firstNonEmpty(
            [
                container.flexibleString(forKey: .name),
                container.flexibleString(forKey: .displayName),
                container.flexibleString(forKey: .type),
                container.flexibleString(forKey: .zone),
                container.flexibleString(forKey: .zoneName),
                container.flexibleString(forKey: .label),
                container.flexibleString(forKey: .path),
                container.flexibleString(forKey: .id)
            ]
        ) ?? "Thermal zone"
        temperatureCelsius = container.flexibleDouble(forKey: .temperatureCelsius)
            ?? container.flexibleDouble(forKey: .temperature)
            ?? container.flexibleDouble(forKey: .value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(temperatureCelsius, forKey: .temperatureCelsius)
    }

    public var id: String { name }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values.lazy.compactMap { $0 }.first(where: { !$0.isEmpty })
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName
        case type
        case zone
        case zoneName
        case label
        case path
        case id
        case temperatureCelsius
        case temperature
        case value
    }
}

public struct SystemComponentSnapshot: Codable, Sendable, Equatable {
    public typealias Battery = SystemComponentBattery
    public typealias ThermalZone = SystemComponentThermalZone

    public let receivedAt: Date?
    public let battery: Battery?
    public let thermalZones: [ThermalZone]

    public init(
        receivedAt: Date? = nil,
        battery: Battery? = nil,
        thermalZones: [ThermalZone] = []
    ) {
        self.receivedAt = receivedAt
        self.battery = battery
        self.thermalZones = thermalZones
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        receivedAt = Self.firstDate(
            in: container,
            keys: [.receivedAt, .capturedAt, .observedAt, .timestamp]
        )
        battery = try? container.decode(Battery.self, forKey: .battery)
        thermalZones = Self.decodeThermalZones(from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(receivedAt, forKey: .receivedAt)
        try container.encodeIfPresent(battery, forKey: .battery)
        try container.encode(thermalZones, forKey: .thermalZones)
    }

    public var hottestThermalZone: ThermalZone? {
        thermalZones
            .filter { $0.temperatureCelsius?.isFinite == true }
            .sorted { lhs, rhs in
                let lhsTemperature = lhs.temperatureCelsius ?? -.infinity
                let rhsTemperature = rhs.temperatureCelsius ?? -.infinity
                if lhsTemperature != rhsTemperature {
                    return lhsTemperature > rhsTemperature
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .first
    }

    private static func firstDate(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Date? {
        for key in keys {
            if let date = try? container.decode(Date.self, forKey: key) {
                return date
            }
            if let seconds = container.flexibleDouble(forKey: key) {
                return Date(timeIntervalSince1970: seconds)
            }
        }
        return nil
    }

    private static func decodeThermalZones(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [ThermalZone] {
        if let zones = try? container.decode([ThermalZone].self, forKey: .thermalZones) {
            return zones
        }
        guard let zoneMap = try? container.decode(
            [String: ThermalZoneMapValue].self,
            forKey: .thermalZones
        ) else {
            return []
        }
        return zoneMap
            .map { name, value in
                ThermalZone(name: value.name ?? name, temperatureCelsius: value.temperatureCelsius)
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private enum CodingKeys: String, CodingKey {
        case receivedAt
        case capturedAt
        case observedAt
        case timestamp
        case battery
        case thermalZones
    }
}

public struct SystemComponentCurrentEnvelope: Codable, Sendable, Equatable, Identifiable {
    public let source: SystemComponentSource
    public let latestSnapshot: SystemComponentSnapshot?
    public let capturedAt: Date?
    public let receivedAt: Date?

    public init(
        source: SystemComponentSource,
        latestSnapshot: SystemComponentSnapshot?,
        capturedAt: Date? = nil,
        receivedAt: Date? = nil
    ) {
        self.source = source
        self.latestSnapshot = latestSnapshot
        self.capturedAt = capturedAt
        self.receivedAt = receivedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nestedSource = try? container.decode(
            SystemComponentSource.self,
            forKey: .source
        ) {
            source = nestedSource
        } else if let nestedComponent = try? container.decode(
            SystemComponentSource.self,
            forKey: .component
        ) {
            source = nestedComponent
        } else {
            source = try SystemComponentSource(from: decoder)
        }
        latestSnapshot = (try? container.decode(
            SystemComponentSnapshot.self,
            forKey: .latestSnapshot
        )) ?? (try? container.decode(SystemComponentSnapshot.self, forKey: .snapshot))
        capturedAt = Self.decodeDate(from: container, forKey: .capturedAt)
        receivedAt = Self.decodeDate(from: container, forKey: .receivedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(latestSnapshot, forKey: .latestSnapshot)
        try container.encodeIfPresent(capturedAt, forKey: .capturedAt)
        try container.encodeIfPresent(receivedAt, forKey: .receivedAt)
    }

    public var id: String { source.id }

    public var freshnessDate: Date? {
        receivedAt ?? capturedAt ?? latestSnapshot?.receivedAt
    }

    private static func decodeDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        if let date = try? container.decode(Date.self, forKey: key) {
            return date
        }
        if let seconds = container.flexibleDouble(forKey: key) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case component
        case latestSnapshot
        case snapshot
        case capturedAt
        case receivedAt
    }
}

public struct SystemComponentCurrentList: Codable, Sendable, Equatable {
    public let items: [SystemComponentCurrentEnvelope]

    public init(items: [SystemComponentCurrentEnvelope]) {
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        if let directItems = try? decoder.singleValueContainer().decode(
            [SystemComponentCurrentEnvelope].self
        ) {
            items = directItems
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let wrappedItems = try? container.decode(
            [SystemComponentCurrentEnvelope].self,
            forKey: .items
        ) {
            items = wrappedItems
        } else if let sources = try? container.decode(
            [SystemComponentCurrentEnvelope].self,
            forKey: .sources
        ) {
            items = sources
        } else if let components = try? container.decode(
            [SystemComponentCurrentEnvelope].self,
            forKey: .components
        ) {
            items = components
        } else if let dataItems = try? container.decode(
            [SystemComponentCurrentEnvelope].self,
            forKey: .data
        ) {
            items = dataItems
        } else if let nested = try? container.decode(SystemComponentCurrentList.self, forKey: .data) {
            items = nested.items
        } else if let single = try? SystemComponentCurrentEnvelope(from: decoder) {
            items = [single]
        } else {
            items = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case sources
        case components
        case data
    }
}

private struct ThermalZoneMapValue: Decodable {
    let name: String?
    let temperatureCelsius: Double?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer() {
            if let number = try? single.decode(Double.self) {
                name = nil
                temperatureCelsius = number
                return
            }
            if let string = try? single.decode(String.self), let number = Double(string) {
                name = nil
                temperatureCelsius = number
                return
            }
            if single.decodeNil() {
                name = nil
                temperatureCelsius = nil
                return
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.flexibleString(forKey: .name)
            ?? container.flexibleString(forKey: .displayName)
            ?? container.flexibleString(forKey: .type)
        temperatureCelsius = container.flexibleDouble(forKey: .temperatureCelsius)
            ?? container.flexibleDouble(forKey: .temperature)
            ?? container.flexibleDouble(forKey: .value)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName
        case type
        case temperatureCelsius
        case temperature
        case value
    }
}

private extension KeyedDecodingContainer {
    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func flexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decode(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}
