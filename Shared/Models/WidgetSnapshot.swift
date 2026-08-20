// swiftlint:disable file_length
//
//  WidgetSnapshot.swift
//  TelephoneBoothOperatorMobile
//
//  Versioned, widget-safe data written by a signed-in host app. Widget
//  extensions never authenticate or perform network requests.
//

import Foundation

// swiftlint:disable:next type_body_length
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 2

    public struct Summary: Codable, Sendable, Equatable {
        public let boothState: BoothState
        public let boothUpdatedAt: Date
        public let pendingMessages: Int
        public let receivedToday: Int
        public let interactionsToday: Int
        public let interactionsInProgress: Int
        public let wsClients: Int
        public let runtimeMode: RuntimeMode?
        public let sourceGeneratedAt: Date?
        public let refreshedAt: Date

        public init(
            boothState: BoothState,
            boothUpdatedAt: Date,
            pendingMessages: Int,
            receivedToday: Int,
            interactionsToday: Int,
            interactionsInProgress: Int,
            wsClients: Int,
            runtimeMode: RuntimeMode?,
            sourceGeneratedAt: Date? = nil,
            refreshedAt: Date
        ) {
            self.boothState = boothState
            self.boothUpdatedAt = boothUpdatedAt
            self.pendingMessages = pendingMessages
            self.receivedToday = receivedToday
            self.interactionsToday = interactionsToday
            self.interactionsInProgress = interactionsInProgress
            self.wsClients = wsClients
            self.runtimeMode = runtimeMode
            self.sourceGeneratedAt = sourceGeneratedAt
            self.refreshedAt = refreshedAt
        }

        public init(stats: StatsSummary, refreshedAt: Date? = nil) {
            self.init(
                boothState: stats.booth.state,
                boothUpdatedAt: stats.booth.updatedAt,
                pendingMessages: stats.messages.badgeCount,
                receivedToday: stats.messages.receivedToday,
                interactionsToday: stats.interactionsToday,
                interactionsInProgress: stats.interactionsInProgress,
                wsClients: stats.realtime.wsClients,
                runtimeMode: stats.booth.runtimeMode,
                sourceGeneratedAt: stats.generatedAt,
                refreshedAt: refreshedAt ?? stats.generatedAt
            )
        }

        fileprivate func hasSameContent(as other: Self) -> Bool {
            boothState == other.boothState
                && boothUpdatedAt == other.boothUpdatedAt
                && pendingMessages == other.pendingMessages
                && receivedToday == other.receivedToday
                && interactionsToday == other.interactionsToday
                && interactionsInProgress == other.interactionsInProgress
                && wsClients == other.wsClients
                && runtimeMode == other.runtimeMode
        }
    }

    public struct LatestMessage: Codable, Sendable, Equatable {
        public let id: String
        public let status: MessageStatus
        public let occurredAt: Date
        public let refreshedAt: Date

        public init(
            id: String,
            status: MessageStatus,
            occurredAt: Date,
            refreshedAt: Date
        ) {
            self.id = id
            self.status = status
            self.occurredAt = occurredAt
            self.refreshedAt = refreshedAt
        }

        public init(message: Message, refreshedAt: Date) {
            self.init(
                id: message.id,
                status: message.status,
                occurredAt: message.receivedAt ?? message.createdAt,
                refreshedAt: refreshedAt
            )
        }

        fileprivate func hasSameContent(as other: Self) -> Bool {
            id == other.id
                && status == other.status
                && occurredAt == other.occurredAt
        }
    }

    public enum HealthSeverity: String, Codable, Sendable, Equatable {
        case nominal
        case warning
        case critical
        case unknown

        fileprivate var rank: Int {
            switch self {
            case .unknown: return 0
            case .nominal: return 1
            case .warning: return 2
            case .critical: return 3
            }
        }

        fileprivate static func maximum(_ values: [Self]) -> Self {
            values.max { $0.rank < $1.rank } ?? .unknown
        }
    }

    public struct SystemHealth: Codable, Sendable, Equatable {
        public let boothId: String
        public let severity: HealthSeverity
        public let cpuTemperatureCelsius: Double?
        public let memoryUsedRatio: Double?
        public let routerTemperatureCelsius: Double?
        public let tailscaleConnected: Bool?
        public let sourceUpdatedAt: Date
        public let refreshedAt: Date

        public init(
            boothId: String,
            severity: HealthSeverity,
            cpuTemperatureCelsius: Double?,
            memoryUsedRatio: Double?,
            routerTemperatureCelsius: Double?,
            tailscaleConnected: Bool?,
            sourceUpdatedAt: Date,
            refreshedAt: Date
        ) {
            self.boothId = boothId
            self.severity = severity
            self.cpuTemperatureCelsius = Self.finite(cpuTemperatureCelsius)
            self.memoryUsedRatio = Self.finite(memoryUsedRatio)
            self.routerTemperatureCelsius = Self.finite(routerTemperatureCelsius)
            self.tailscaleConnected = tailscaleConnected
            self.sourceUpdatedAt = sourceUpdatedAt
            self.refreshedAt = refreshedAt
        }

        public init(
            envelope: BoothSystemSnapshotEnvelope,
            components: [SystemComponentCurrentEnvelope],
            refreshedAt: Date
        ) {
            let snapshot = envelope.snapshot
            let routerTemperature = Self.routerTemperature(
                in: components,
                boothId: envelope.boothId,
                now: refreshedAt
            )
            self.init(
                boothId: envelope.boothId,
                severity: Self.evaluate(
                    snapshot: snapshot,
                    routerTemperature: routerTemperature,
                    sourceUpdatedAt: envelope.receivedAt,
                    now: refreshedAt
                ),
                cpuTemperatureCelsius: snapshot.cpuTemperatureCelsius,
                memoryUsedRatio: snapshot.memoryUsedRatio,
                routerTemperatureCelsius: routerTemperature,
                tailscaleConnected: snapshot.tailscaleConnected,
                sourceUpdatedAt: envelope.receivedAt,
                refreshedAt: refreshedAt
            )
        }

        public func effectiveSeverity(
            at date: Date,
            staleAfter interval: TimeInterval = WidgetSnapshot.sourceStaleInterval
        ) -> HealthSeverity {
            guard date.timeIntervalSince(sourceUpdatedAt) >= interval else {
                return severity
            }
            return HealthSeverity.maximum([severity, .warning])
        }

        fileprivate func hasSameContent(as other: Self) -> Bool {
            boothId == other.boothId
                && severity == other.severity
                && cpuTemperatureCelsius == other.cpuTemperatureCelsius
                && memoryUsedRatio == other.memoryUsedRatio
                && routerTemperatureCelsius == other.routerTemperatureCelsius
                && tailscaleConnected == other.tailscaleConnected
                && sourceUpdatedAt == other.sourceUpdatedAt
        }

        private static func evaluate(
            snapshot: BoothSystemSnapshot,
            routerTemperature: Double?,
            sourceUpdatedAt: Date,
            now: Date
        ) -> HealthSeverity {
            let temperatures = [
                temperatureSeverity(snapshot.cpuTemperatureCelsius),
                temperatureSeverity(routerTemperature)
            ]
            let hasNumericSignal = [
                snapshot.cpuTemperatureCelsius,
                routerTemperature,
                snapshot.memoryUsedRatio,
                snapshot.loadAverage1m
            ].contains { $0?.isFinite == true }
            guard hasNumericSignal
                    || snapshot.tailscaleConnected != nil
                    || snapshot.throttlingFlags != nil else {
                return .unknown
            }

            var values = temperatures + [
                memorySeverity(snapshot.memoryUsedRatio),
                loadSeverity(snapshot.loadAverage1m, cores: snapshot.cpuCoreCount)
            ]
            if snapshot.tailscaleConnected == false { values.append(.critical) }
            if snapshot.throttlingFlags?.isEmpty == false { values.append(.warning) }
            if now.timeIntervalSince(sourceUpdatedAt) >= WidgetSnapshot.sourceStaleInterval {
                values.append(.warning)
            }
            return HealthSeverity.maximum(values)
        }

        private static func temperatureSeverity(_ value: Double?) -> HealthSeverity {
            guard let value, value.isFinite else { return .nominal }
            if value >= 75 { return .critical }
            if value >= 60 { return .warning }
            return .nominal
        }

        private static func memorySeverity(_ value: Double?) -> HealthSeverity {
            guard let value, value.isFinite else { return .nominal }
            if value >= 0.95 { return .critical }
            if value >= 0.85 { return .warning }
            return .nominal
        }

        private static func loadSeverity(_ value: Double?, cores: Int?) -> HealthSeverity {
            guard let value, value.isFinite else { return .nominal }
            let reference = Double(max(cores ?? 1, 1))
            if value >= reference * 2 { return .critical }
            if value >= reference { return .warning }
            return .nominal
        }

        private static func routerTemperature(
            in components: [SystemComponentCurrentEnvelope],
            boothId: String,
            now: Date
        ) -> Double? {
            components
                .filter { $0.source.boothId == boothId && $0.source.isRouter }
                .sorted {
                    let nameOrder = $0.source.effectiveDisplayName.localizedCaseInsensitiveCompare(
                        $1.source.effectiveDisplayName
                    )
                    if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                    return $0.id < $1.id
                }
                .compactMap { component -> Double? in
                    guard let freshnessDate = component.freshnessDate,
                          now.timeIntervalSince(freshnessDate) <= WidgetSnapshot.sourceStaleInterval,
                          let value = component.latestSnapshot?.battery?.temperatureCelsius,
                          value.isFinite else {
                        return nil
                    }
                    return value
                }
                .first
        }

        private static func finite(_ value: Double?) -> Double? {
            guard let value, value.isFinite else { return nil }
            return value
        }
    }

    public struct ActivityBucket: Codable, Sendable, Equatable, Identifiable {
        public let hour: Int
        public let pickups: Int
        public let messages: Int

        public init(hour: Int, pickups: Int, messages: Int) {
            self.hour = hour
            self.pickups = pickups
            self.messages = messages
        }

        public var id: Int { hour }
    }

    public struct Activity: Codable, Sendable, Equatable {
        public let pickups: Int
        public let messages: Int
        public let buckets: [ActivityBucket]
        public let rangeStart: Date?
        public let rangeEnd: Date
        public let refreshedAt: Date

        public init(
            pickups: Int,
            messages: Int,
            buckets: [ActivityBucket],
            rangeStart: Date?,
            rangeEnd: Date,
            refreshedAt: Date
        ) {
            self.pickups = pickups
            self.messages = messages
            self.buckets = Array(buckets.prefix(24))
            self.rangeStart = rangeStart
            self.rangeEnd = rangeEnd
            self.refreshedAt = refreshedAt
        }

        public init(overview: StatsOverview, refreshedAt: Date) {
            self.init(
                pickups: overview.interactionMetrics.total,
                messages: overview.messages.allRecordingsCount,
                buckets: overview.hourly.map {
                    ActivityBucket(
                        hour: $0.hour,
                        pickups: $0.interactionCount,
                        messages: $0.messages
                    )
                },
                rangeStart: overview.rangeStart,
                rangeEnd: overview.rangeEnd,
                refreshedAt: refreshedAt
            )
        }

        fileprivate func hasSameContent(as other: Self) -> Bool {
            pickups == other.pickups
                && messages == other.messages
                && buckets == other.buckets
        }
    }

    public static let cacheStaleInterval: TimeInterval = 30 * 60
    public static let sourceStaleInterval: TimeInterval = 5 * 60

    public let schemaVersion: Int
    public let summary: Summary?
    public let latestMessage: LatestMessage?
    public let systemHealth: SystemHealth?
    public let activity: Activity?
    public let writtenAt: Date

    public init(
        schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
        summary: Summary? = nil,
        latestMessage: LatestMessage? = nil,
        systemHealth: SystemHealth? = nil,
        activity: Activity? = nil,
        writtenAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.summary = summary
        self.latestMessage = latestMessage
        self.systemHealth = systemHealth
        self.activity = activity
        self.writtenAt = writtenAt
    }

    public init(
        boothState: BoothState,
        boothUpdatedAt: Date,
        pendingMessages: Int,
        receivedToday: Int,
        callsToday: Int,
        callsInProgress: Int,
        wsClients: Int,
        generatedAt: Date,
        runtimeMode: RuntimeMode? = nil
    ) {
        self.init(
            summary: Summary(
                boothState: boothState,
                boothUpdatedAt: boothUpdatedAt,
                pendingMessages: pendingMessages,
                receivedToday: receivedToday,
                interactionsToday: callsToday,
                interactionsInProgress: callsInProgress,
                wsClients: wsClients,
                runtimeMode: runtimeMode,
                sourceGeneratedAt: generatedAt,
                refreshedAt: generatedAt
            ),
            writtenAt: generatedAt
        )
    }

    public init(stats: StatsSummary) {
        self.init(summary: Summary(stats: stats), writtenAt: stats.generatedAt)
    }

    public var boothState: BoothState { summary?.boothState ?? .idle }
    public var boothUpdatedAt: Date { summary?.boothUpdatedAt ?? writtenAt }
    public var pendingMessages: Int { summary?.pendingMessages ?? 0 }
    public var receivedToday: Int { summary?.receivedToday ?? 0 }
    public var callsToday: Int { summary?.interactionsToday ?? 0 }
    public var callsInProgress: Int { summary?.interactionsInProgress ?? 0 }
    public var interactionsToday: Int { callsToday }
    public var interactionsInProgress: Int { callsInProgress }
    public var wsClients: Int { summary?.wsClients ?? 0 }
    public var generatedAt: Date { summary?.refreshedAt ?? writtenAt }
    public var runtimeMode: RuntimeMode? { summary?.runtimeMode }

    public func isStale(
        sectionDate: Date,
        at date: Date,
        interval: TimeInterval = WidgetSnapshot.cacheStaleInterval
    ) -> Bool {
        date.timeIntervalSince(sectionDate) >= interval
    }

    public func hasSameContent(as other: WidgetSnapshot) -> Bool {
        Self.sameOptional(summary, other.summary) { $0.hasSameContent(as: $1) }
            && Self.sameOptional(latestMessage, other.latestMessage) {
                $0.hasSameContent(as: $1)
            }
            && Self.sameOptional(systemHealth, other.systemHealth) {
                $0.hasSameContent(as: $1)
            }
            && Self.sameOptional(activity, other.activity) {
                $0.hasSameContent(as: $1)
            }
    }

    private static func sameOptional<Value>(
        _ lhs: Value?,
        _ rhs: Value?,
        comparison: (Value, Value) -> Bool
    ) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case (.some(let lhs), .some(let rhs)): return comparison(lhs, rhs)
        default: return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case summary
        case latestMessage
        case systemHealth
        case activity
        case writtenAt

        // Version 1 keys.
        case boothState
        case boothUpdatedAt
        case pendingMessages
        case receivedToday
        case callsToday
        case callsInProgress
        case wsClients
        case generatedAt
        case runtimeMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        if let decodedSummary = try container.decodeIfPresent(Summary.self, forKey: .summary) {
            summary = decodedSummary
        } else if container.contains(.boothState) {
            let generatedAt = try container.decode(Date.self, forKey: .generatedAt)
            summary = Summary(
                boothState: try container.decode(BoothState.self, forKey: .boothState),
                boothUpdatedAt: try container.decode(Date.self, forKey: .boothUpdatedAt),
                pendingMessages: try container.decode(Int.self, forKey: .pendingMessages),
                receivedToday: try container.decode(Int.self, forKey: .receivedToday),
                interactionsToday: try container.decode(Int.self, forKey: .callsToday),
                interactionsInProgress: try container.decode(Int.self, forKey: .callsInProgress),
                wsClients: try container.decode(Int.self, forKey: .wsClients),
                runtimeMode: try container.decodeIfPresent(RuntimeMode.self, forKey: .runtimeMode),
                sourceGeneratedAt: generatedAt,
                refreshedAt: generatedAt
            )
        } else {
            summary = nil
        }

        latestMessage = try container.decodeIfPresent(LatestMessage.self, forKey: .latestMessage)
        systemHealth = try container.decodeIfPresent(SystemHealth.self, forKey: .systemHealth)
        activity = try container.decodeIfPresent(Activity.self, forKey: .activity)
        writtenAt = try container.decodeIfPresent(Date.self, forKey: .writtenAt)
            ?? summary?.refreshedAt
            ?? Date(timeIntervalSince1970: 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(latestMessage, forKey: .latestMessage)
        try container.encodeIfPresent(systemHealth, forKey: .systemHealth)
        try container.encodeIfPresent(activity, forKey: .activity)
        try container.encode(writtenAt, forKey: .writtenAt)
    }
}

public extension WidgetSnapshot {
    static let placeholder: WidgetSnapshot = {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return WidgetSnapshot(
            summary: Summary(
                boothState: .idle,
                boothUpdatedAt: date,
                pendingMessages: 2,
                receivedToday: 7,
                interactionsToday: 4,
                interactionsInProgress: 0,
                wsClients: 1,
                runtimeMode: nil,
                sourceGeneratedAt: date,
                refreshedAt: date
            ),
            latestMessage: LatestMessage(
                id: "preview-message",
                status: .received,
                occurredAt: date.addingTimeInterval(-8 * 60),
                refreshedAt: date
            ),
            systemHealth: SystemHealth(
                boothId: "booth",
                severity: .nominal,
                cpuTemperatureCelsius: 48.5,
                memoryUsedRatio: 0.43,
                routerTemperatureCelsius: 42.1,
                tailscaleConnected: true,
                sourceUpdatedAt: date,
                refreshedAt: date
            ),
            activity: Activity(
                pickups: 18,
                messages: 7,
                buckets: (0..<24).map {
                    ActivityBucket(hour: $0, pickups: $0 % 5, messages: $0 % 3)
                },
                rangeStart: date.addingTimeInterval(-24 * 60 * 60),
                rangeEnd: date,
                refreshedAt: date
            ),
            writtenAt: date
        )
    }()
}
