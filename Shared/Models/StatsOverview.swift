//
//  StatsOverview.swift
//  TelephoneBoothOperatorMobile
//
//  Mirrors the operator's `StatsOverviewSchema` returned by
//  `GET /v1/stats/overview?window=…`. All time bucketing is UTC on the
//  server; the response envelope carries `timezone: "UTC"` so clients
//  reformat for the local operator.
//
//  Enum-keyed records (`outcomes`, `byStatus`, `digitsDialed`) are kept
//  as `[String: Int]` so unknown server-side enum additions don't break
//  decode. Ordered-display helpers below render canonical enum order
//  first with unknown keys appended in sorted order.
//

import Foundation

public enum StatsWindow: Codable, Sendable, Hashable {
    case last24h
    case last7d
    case last30d
    case all
    case unknown(String)

    public static let knownCases: [StatsWindow] = [.last24h, .last7d, .last30d, .all]

    public var rawValue: String {
        switch self {
        case .last24h: return "24h"
        case .last7d: return "7d"
        case .last30d: return "30d"
        case .all: return "all"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "24h": self = .last24h
        case "7d": self = .last7d
        case "30d": self = .last30d
        case "all": self = .all
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
        switch self {
        case .last24h: return "Last 24 hours"
        case .last7d: return "Last 7 days"
        case .last30d: return "Last 30 days"
        case .all: return "All time"
        case .unknown(let value): return value
        }
    }

    public var shortLabel: String {
        switch self {
        case .last24h: return "24h"
        case .last7d: return "7d"
        case .last30d: return "30d"
        case .all: return "All"
        case .unknown(let value): return value
        }
    }
}

public struct StatsOverview: Codable, Sendable, Hashable {
    public let window: StatsWindow
    public let rangeStart: Date?
    public let rangeEnd: Date
    public let generatedAt: Date
    public let timezone: String
    public let calls: Calls
    public let messages: Messages
    public let playback: Playback
    public let pickupsHangups: PickupsHangups
    public let uploads: Uploads
    public let topQuestions: [TopQuestion]
    public let hourly: [HourlyBucket]
    public let busiest: Busiest
    public let lastActivityAt: Date?
    public let boothBreakdown: [BoothBreakdown]

    public struct Calls: Codable, Sendable, Hashable {
        public let total: Int
        public let completed: Int
        public let inProgress: Int
        public let averageDurationMs: Double?
        public let longestDurationMs: Double?
        public let outcomes: [String: Int]
        public let perDay: [PerDay]

        public init(
            total: Int,
            completed: Int,
            inProgress: Int,
            averageDurationMs: Double?,
            longestDurationMs: Double?,
            outcomes: [String: Int],
            perDay: [PerDay]
        ) {
            self.total = total
            self.completed = completed
            self.inProgress = inProgress
            self.averageDurationMs = averageDurationMs
            self.longestDurationMs = longestDurationMs
            self.outcomes = outcomes
            self.perDay = perDay
        }
    }

    public struct PerDay: Codable, Sendable, Hashable {
        public let date: String      // YYYY-MM-DD (UTC)
        public let total: Int
        public let completed: Int

        public init(date: String, total: Int, completed: Int) {
            self.date = date
            self.total = total
            self.completed = completed
        }
    }

    public struct Messages: Codable, Sendable, Hashable {
        public let total: Int
        public let byStatus: [String: Int]
        public let averageDurationMs: Double?

        public init(total: Int, byStatus: [String: Int], averageDurationMs: Double?) {
            self.total = total
            self.byStatus = byStatus
            self.averageDurationMs = averageDurationMs
        }
    }

    public struct Playback: Codable, Sendable, Hashable {
        public let totalPlaybacks: Int

        public init(totalPlaybacks: Int) {
            self.totalPlaybacks = totalPlaybacks
        }
    }

    public struct PickupsHangups: Codable, Sendable, Hashable {
        public let pickups: Int
        public let hangups: Int
        public let digitsDialed: [String: Int]

        public init(pickups: Int, hangups: Int, digitsDialed: [String: Int]) {
            self.pickups = pickups
            self.hangups = hangups
            self.digitsDialed = digitsDialed
        }
    }

    public struct Uploads: Codable, Sendable, Hashable {
        public let succeeded: Int
        public let failed: Int
        public let failureRate: Double?

        public init(succeeded: Int, failed: Int, failureRate: Double?) {
            self.succeeded = succeeded
            self.failed = failed
            self.failureRate = failureRate
        }
    }

    public struct TopQuestion: Codable, Sendable, Hashable, Identifiable {
        public let questionId: UUID
        public let prompt: String
        public let messageCount: Int
        public let lastUsedAt: Date?
        public let retiredAt: Date?

        public var id: UUID { questionId }

        public init(
            questionId: UUID,
            prompt: String,
            messageCount: Int,
            lastUsedAt: Date?,
            retiredAt: Date?
        ) {
            self.questionId = questionId
            self.prompt = prompt
            self.messageCount = messageCount
            self.lastUsedAt = lastUsedAt
            self.retiredAt = retiredAt
        }
    }

    public struct HourlyBucket: Codable, Sendable, Hashable, Identifiable {
        public let hour: Int
        public let calls: Int
        public let messages: Int

        public var id: Int { hour }

        public init(hour: Int, calls: Int, messages: Int) {
            self.hour = hour
            self.calls = calls
            self.messages = messages
        }
    }

    public struct Busiest: Codable, Sendable, Hashable {
        public let hour: Int?
        public let dayOfWeek: Int?

        public init(hour: Int?, dayOfWeek: Int?) {
            self.hour = hour
            self.dayOfWeek = dayOfWeek
        }
    }

    public struct BoothBreakdown: Codable, Sendable, Hashable, Identifiable {
        public let boothId: String
        public let calls: Int
        public let messages: Int?
        public let lastSeenAt: Date?

        public var id: String { boothId }

        public init(boothId: String, calls: Int, messages: Int?, lastSeenAt: Date?) {
            self.boothId = boothId
            self.calls = calls
            self.messages = messages
            self.lastSeenAt = lastSeenAt
        }
    }

    public init(
        window: StatsWindow,
        rangeStart: Date?,
        rangeEnd: Date,
        generatedAt: Date,
        timezone: String,
        calls: Calls,
        messages: Messages,
        playback: Playback,
        pickupsHangups: PickupsHangups,
        uploads: Uploads,
        topQuestions: [TopQuestion],
        hourly: [HourlyBucket],
        busiest: Busiest,
        lastActivityAt: Date?,
        boothBreakdown: [BoothBreakdown]
    ) {
        self.window = window
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.generatedAt = generatedAt
        self.timezone = timezone
        self.calls = calls
        self.messages = messages
        self.playback = playback
        self.pickupsHangups = pickupsHangups
        self.uploads = uploads
        self.topQuestions = topQuestions
        self.hourly = hourly
        self.busiest = busiest
        self.lastActivityAt = lastActivityAt
        self.boothBreakdown = boothBreakdown
    }
}

// MARK: - Display helpers

public extension StatsOverview {
    /// Completion rate (calls.completed / calls.total) when there were any
    /// calls in the window, otherwise `nil` so the UI can show "—".
    var completionRate: Double? {
        guard calls.total > 0 else { return nil }
        return Double(calls.completed) / Double(calls.total)
    }

    /// Time elapsed since the most recent booth telemetry event.
    /// `nil` when the booth has never reported any events.
    var quietForSeconds: TimeInterval? {
        guard let lastActivityAt else { return nil }
        return max(0, Date().timeIntervalSince(lastActivityAt))
    }
}

public extension StatsOverview.Uploads {
    var total: Int { succeeded + failed }
}

public extension StatsOverview.PickupsHangups {
    /// Returns `["0": 0, ..., "9": 0]` overlaid with whatever the server sent,
    /// so the UI can always show 10 cells regardless of which digits were
    /// dialed in the window.
    func digitsDialedZeroFilled() -> [(digit: String, count: Int)] {
        (0...9).map { idx -> (digit: String, count: Int) in
            let key = String(idx)
            return (digit: key, count: digitsDialed[key] ?? 0)
        }
    }
}

public extension StatsOverview {
    /// Canonical outcome ordering matching `CallOutcomeSchema` on the server.
    /// Unknown server-supplied keys are appended sorted so forward-compat
    /// additions still render somewhere sensible.
    static let canonicalOutcomeOrder: [String] = [
        "recording_completed",
        "hung_up_before_dial",
        "hung_up_during_prompt",
        "hung_up_during_recording",
        "hung_up_during_upload",
        "recording_failed",
        "upload_failed",
        "operator_error",
        "aborted"
    ]

    /// Workflow order for message statuses (matches `MessageStatusSchema`).
    static let canonicalStatusOrder: [String] = [
        "uploading",
        "received",
        "pending",
        "approved",
        "rejected"
    ]

    func outcomesInDisplayOrder() -> [(key: String, count: Int)] {
        ordered(calls.outcomes, canonical: Self.canonicalOutcomeOrder)
    }

    func statusesInDisplayOrder() -> [(key: String, count: Int)] {
        ordered(messages.byStatus, canonical: Self.canonicalStatusOrder)
    }

    private func ordered(
        _ record: [String: Int],
        canonical: [String]
    ) -> [(key: String, count: Int)] {
        var known: [(key: String, count: Int)] = []
        var seen = Set<String>()
        for key in canonical {
            if let count = record[key] {
                known.append((key, count))
                seen.insert(key)
            }
        }
        let unknown = record.keys
            .filter { !seen.contains($0) }
            .sorted()
            .map { (key: $0, count: record[$0] ?? 0) }
        return known + unknown
    }
}

// MARK: - Localized labels

public extension StatsOverview {
    static func outcomeLabel(_ key: String) -> String {
        switch key {
        case "recording_completed": return "Recording completed"
        case "hung_up_before_dial": return "Hung up before dialing"
        case "hung_up_during_prompt": return "Hung up during prompt"
        case "hung_up_during_recording": return "Hung up during recording"
        case "hung_up_during_upload": return "Hung up during upload"
        case "recording_failed": return "Recording failed"
        case "upload_failed": return "Upload failed"
        case "operator_error": return "Operator error"
        case "aborted": return "Aborted"
        default: return key
        }
    }

    static func statusLabel(_ key: String) -> String {
        switch key {
        case "uploading": return "Uploading"
        case "received": return "Received"
        case "pending": return "Pending"
        case "approved": return "Approved"
        case "rejected": return "Rejected"
        default: return key
        }
    }

    static func dayOfWeekLabel(_ index: Int) -> String? {
        let names = [
            "Sunday", "Monday", "Tuesday", "Wednesday",
            "Thursday", "Friday", "Saturday"
        ]
        guard index >= 0, index < names.count else { return nil }
        return names[index]
    }
}
