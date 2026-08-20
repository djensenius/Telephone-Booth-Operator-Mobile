// swiftlint:disable file_length
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
    public let interactions: Interactions?
    public let actions: Actions?
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
        public let completed: Int?
        public let noSelection: Int?
        public let messagesLeft: Int?

        public init(
            date: String,
            total: Int,
            completed: Int? = nil,
            noSelection: Int? = nil,
            messagesLeft: Int? = nil
        ) {
            self.date = date
            self.total = total
            self.completed = completed
            self.noSelection = noSelection
            self.messagesLeft = messagesLeft
        }
    }

    public struct Interactions: Codable, Sendable, Hashable {
        public let total: Int
        public let inProgressNow: Int
        public let noSelection: Int
        public let messagesLeft: Int
        public let averageDurationMs: Double?
        public let longestDurationMs: Double?
        public let outcomes: [String: Int]
        public let perDay: [PerDay]

        public init(
            total: Int,
            inProgressNow: Int,
            noSelection: Int,
            messagesLeft: Int,
            averageDurationMs: Double?,
            longestDurationMs: Double?,
            outcomes: [String: Int],
            perDay: [PerDay]
        ) {
            self.total = total
            self.inProgressNow = inProgressNow
            self.noSelection = noSelection
            self.messagesLeft = messagesLeft
            self.averageDurationMs = averageDurationMs
            self.longestDurationMs = longestDurationMs
            self.outcomes = outcomes
            self.perDay = perDay
        }
    }

    public struct Messages: Codable, Sendable, Hashable {
        /// Retained for older server versions.
        public let total: Int
        public let approved: Int?
        public let allRecordings: Int?
        public let byStatus: [String: Int]
        public let averageDurationMs: Double?

        public init(
            total: Int,
            approved: Int? = nil,
            allRecordings: Int? = nil,
            byStatus: [String: Int],
            averageDurationMs: Double?
        ) {
            self.total = total
            self.approved = approved
            self.allRecordings = allRecordings
            self.byStatus = byStatus
            self.averageDurationMs = averageDurationMs
        }

        public var approvedCount: Int { approved ?? byStatus["approved"] ?? total }
        public var allRecordingsCount: Int { allRecordings ?? total }
    }

    public struct Playback: Codable, Sendable, Hashable {
        /// Legacy combined booth playbacks; newer payloads split message and
        /// instruction starts in `actions`.
        public let totalPlaybacks: Int

        public init(totalPlaybacks: Int) {
            self.totalPlaybacks = totalPlaybacks
        }
    }

    public struct Actions: Codable, Sendable, Hashable {
        public let digitsDialed: [String: Int]
        public let leaveMessageSelections: Int
        public let listenMessageSelections: Int
        public let instructionSelections: Int
        public let wrongNumberAttempts: Int
        public let messagePlaybackStarts: Int
        public let instructionPlaybackStarts: Int

        public init(
            digitsDialed: [String: Int],
            leaveMessageSelections: Int,
            listenMessageSelections: Int,
            instructionSelections: Int,
            wrongNumberAttempts: Int,
            messagePlaybackStarts: Int,
            instructionPlaybackStarts: Int
        ) {
            self.digitsDialed = digitsDialed
            self.leaveMessageSelections = leaveMessageSelections
            self.listenMessageSelections = listenMessageSelections
            self.instructionSelections = instructionSelections
            self.wrongNumberAttempts = wrongNumberAttempts
            self.messagePlaybackStarts = messagePlaybackStarts
            self.instructionPlaybackStarts = instructionPlaybackStarts
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
        public let interactions: Int?
        public let messages: Int

        public var id: Int { hour }

        public init(
            hour: Int,
            calls: Int,
            interactions: Int? = nil,
            messages: Int
        ) {
            self.hour = hour
            self.calls = calls
            self.interactions = interactions
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
        public let interactions: Int?
        public let messages: Int?
        public let lastSeenAt: Date?

        public var id: String { boothId }

        public init(
            boothId: String,
            calls: Int,
            interactions: Int? = nil,
            messages: Int?,
            lastSeenAt: Date?
        ) {
            self.boothId = boothId
            self.calls = calls
            self.interactions = interactions
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
        interactions: Interactions? = nil,
        actions: Actions? = nil,
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
        self.interactions = interactions
        self.actions = actions
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
    enum ActionMetricSource: Sendable, Hashable {
        case additivePayload
        case legacyFallback
    }

    struct ActionMetrics: Sendable, Hashable {
        public let digitsDialed: [String: Int]
        public let leaveMessageSelections: Int
        public let listenMessageSelections: Int
        public let instructionSelections: Int
        public let wrongNumberAttempts: Int
        public let messagePlaybackStarts: Int?
        public let instructionPlaybackStarts: Int?
        public let combinedPlaybackStarts: Int?
        public let source: ActionMetricSource

        public var supportsPlaybackBreakouts: Bool {
            messagePlaybackStarts != nil && instructionPlaybackStarts != nil
        }

        public var totalSelections: Int {
            leaveMessageSelections + listenMessageSelections + instructionSelections
        }

        public var totalPlaybackStarts: Int? {
            if let messagePlaybackStarts, let instructionPlaybackStarts {
                return messagePlaybackStarts + instructionPlaybackStarts
            }
            return combinedPlaybackStarts
        }

        public func digitsDialedZeroFilled() -> [(digit: String, count: Int)] {
            (0...9).map { idx -> (digit: String, count: Int) in
                let key = String(idx)
                return (digit: key, count: digitsDialed[key] ?? 0)
            }
        }
    }

    struct SelectionFunnel: Identifiable, Sendable, Hashable {
        public let id: String
        public let selectionLabel: String
        public let selectionCount: Int
        public let outcomeLabel: String
        public let outcomeCount: Int?
    }

    var interactionMetrics: Interactions {
        interactions ?? Interactions(legacyCalls: calls)
    }

    var actionMetrics: ActionMetrics {
        if let actions {
            return ActionMetrics(
                digitsDialed: actions.digitsDialed,
                leaveMessageSelections: actions.leaveMessageSelections,
                listenMessageSelections: actions.listenMessageSelections,
                instructionSelections: actions.instructionSelections,
                wrongNumberAttempts: actions.wrongNumberAttempts,
                messagePlaybackStarts: actions.messagePlaybackStarts,
                instructionPlaybackStarts: actions.instructionPlaybackStarts,
                combinedPlaybackStarts: actions.messagePlaybackStarts + actions.instructionPlaybackStarts,
                source: .additivePayload
            )
        }

        let digits = pickupsHangups.digitsDialed
        let wrongNumbers = (3...9)
            .map { digits[String($0)] ?? 0 }
            .reduce(0, +)
        let combinedPlaybackStarts = playback.totalPlaybacks > 0 ? playback.totalPlaybacks : nil
        return ActionMetrics(
            digitsDialed: digits,
            leaveMessageSelections: digits["1"] ?? 0,
            listenMessageSelections: digits["2"] ?? 0,
            instructionSelections: digits["0"] ?? 0,
            wrongNumberAttempts: wrongNumbers,
            messagePlaybackStarts: nil,
            instructionPlaybackStarts: nil,
            combinedPlaybackStarts: combinedPlaybackStarts,
            source: .legacyFallback
        )
    }

    var selectionFunnels: [SelectionFunnel] {
        let actions = actionMetrics
        let interactions = interactionMetrics
        return [
            SelectionFunnel(
                id: "leave-message",
                selectionLabel: "Leave message",
                selectionCount: actions.leaveMessageSelections,
                outcomeLabel: "Messages left",
                outcomeCount: interactions.messagesLeft
            ),
            SelectionFunnel(
                id: "listen-message",
                selectionLabel: "Listen message",
                selectionCount: actions.listenMessageSelections,
                outcomeLabel: "Message playback starts",
                outcomeCount: actions.messagePlaybackStarts
            ),
            SelectionFunnel(
                id: "instructions",
                selectionLabel: "Instructions",
                selectionCount: actions.instructionSelections,
                outcomeLabel: "Instruction playback starts",
                outcomeCount: actions.instructionPlaybackStarts
            )
        ]
    }

    /// Message-left rate for the selected interaction cohort. Falls back to
    /// the legacy `calls.completed / calls.total` semantics while older
    /// Operator deployments are still in use.
    var completionRate: Double? {
        guard interactionMetrics.total > 0 else { return nil }
        return Double(interactionMetrics.messagesLeft) / Double(interactionMetrics.total)
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

public extension StatsOverview.PerDay {
    var messagesLeftCount: Int { messagesLeft ?? completed ?? 0 }
    var noSelectionCount: Int { noSelection ?? 0 }
}

public extension StatsOverview.HourlyBucket {
    var interactionCount: Int { interactions ?? calls }
}

public extension StatsOverview.BoothBreakdown {
    var interactionCount: Int { interactions ?? calls }
}

private extension StatsOverview.Interactions {
    init(legacyCalls: StatsOverview.Calls) {
        self.init(
            total: legacyCalls.total,
            inProgressNow: legacyCalls.inProgress,
            noSelection: legacyCalls.outcomes["hung_up_before_dial"] ?? 0,
            messagesLeft: legacyCalls.outcomes["recording_completed"] ?? legacyCalls.completed,
            averageDurationMs: legacyCalls.averageDurationMs,
            longestDurationMs: legacyCalls.longestDurationMs,
            outcomes: legacyCalls.outcomes,
            perDay: legacyCalls.perDay.map {
                StatsOverview.PerDay(
                    date: $0.date,
                    total: $0.total,
                    completed: $0.completed,
                    noSelection: $0.noSelection,
                    messagesLeft: $0.messagesLeft ?? $0.completed
                )
            }
        )
    }
}

public enum InstallationScope: Sendable, Hashable {
    case current
    case installation(String)
    case all

    public var queryValue: String? {
        switch self {
        case .current: return nil
        case .installation(let id): return id
        case .all: return "all"
        }
    }

    public var displayName: String {
        switch self {
        case .current: return "Current Installation"
        case .installation: return "Historical Installation"
        case .all: return "All Installations"
        }
    }
}

public struct InstallationSummary: Codable, Sendable, Hashable {
    public let calls: Int
    public let interactions: Int?
    public let interactionBreakdown: InteractionBreakdown?
    public let messages: Int
    public let allRecordings: Int?
    public let byStatus: [String: Int]?
    public let messagesApproved: Int?
    public let messagesRejected: Int?
    public let questions: Int
    public let events: Int
    public let recordedMs: Int
    public let firstActivityAt: Date?
    public let lastActivityAt: Date?

    public struct InteractionBreakdown: Codable, Sendable, Hashable {
        public let noSelection: Int
        public let wrongNumberAttempts: Int
        public let messagesLeft: Int
        public let messagePlaybackStarts: Int
        public let instructionPlaybackStarts: Int

        public init(
            noSelection: Int,
            wrongNumberAttempts: Int,
            messagesLeft: Int,
            messagePlaybackStarts: Int,
            instructionPlaybackStarts: Int
        ) {
            self.noSelection = noSelection
            self.wrongNumberAttempts = wrongNumberAttempts
            self.messagesLeft = messagesLeft
            self.messagePlaybackStarts = messagePlaybackStarts
            self.instructionPlaybackStarts = instructionPlaybackStarts
        }
    }

    public init(
        calls: Int,
        interactions: Int? = nil,
        interactionBreakdown: InteractionBreakdown? = nil,
        messages: Int,
        allRecordings: Int? = nil,
        byStatus: [String: Int]? = nil,
        messagesApproved: Int? = nil,
        messagesRejected: Int? = nil,
        questions: Int,
        events: Int,
        recordedMs: Int,
        firstActivityAt: Date?,
        lastActivityAt: Date?
    ) {
        self.calls = calls
        self.interactions = interactions
        self.interactionBreakdown = interactionBreakdown
        self.messages = messages
        self.allRecordings = allRecordings
        self.byStatus = byStatus
        self.messagesApproved = messagesApproved
        self.messagesRejected = messagesRejected
        self.questions = questions
        self.events = events
        self.recordedMs = recordedMs
        self.firstActivityAt = firstActivityAt
        self.lastActivityAt = lastActivityAt
    }
}

public extension InstallationSummary {
    var interactionTotal: Int { interactions ?? calls }
    var messagesLeftCount: Int { interactionBreakdown?.messagesLeft ?? allRecordings ?? messages }
}

public struct Installation: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let notes: String?
    public let location: String?
    public let defaultTranscriptionLanguage: String?
    public let startedAt: Date
    public let endedAt: Date?
    public let endedById: String?
    public let summary: InstallationSummary?
    public let createdAt: Date
    public let isActive: Bool

    public init(
        id: String,
        name: String,
        notes: String?,
        location: String?,
        defaultTranscriptionLanguage: String? = nil,
        startedAt: Date,
        endedAt: Date?,
        endedById: String?,
        summary: InstallationSummary?,
        createdAt: Date,
        isActive: Bool
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.location = location
        self.defaultTranscriptionLanguage = defaultTranscriptionLanguage
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endedById = endedById
        self.summary = summary
        self.createdAt = createdAt
        self.isActive = isActive
    }
}

public struct InstallationList: Codable, Sendable, Hashable {
    public let items: [Installation]

    public init(items: [Installation]) {
        self.items = items
    }
}

public struct InstallationUpdateRequest: Codable, Sendable, Hashable {
    public let defaultTranscriptionLanguage: String?

    public init(defaultTranscriptionLanguage: String?) {
        self.defaultTranscriptionLanguage = defaultTranscriptionLanguage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case defaultTranscriptionLanguage
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultTranscriptionLanguage, forKey: .defaultTranscriptionLanguage)
    }
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
        "installation_ended",
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
        ordered(interactionMetrics.outcomes, canonical: Self.canonicalOutcomeOrder)
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
        outcomeLabels[key] ?? key
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

    private static let outcomeLabels: [String: String] = [
        "recording_completed": "Recording completed",
        "hung_up_before_dial": "Hung up before dialing",
        "hung_up_during_prompt": "Hung up during prompt",
        "hung_up_during_recording": "Hung up during recording",
        "hung_up_during_upload": "Hung up during upload",
        "recording_failed": "Recording failed",
        "upload_failed": "Upload failed",
        "operator_error": "Operator error",
        "installation_ended": "Installation ended",
        "aborted": "Aborted"
    ]
}
