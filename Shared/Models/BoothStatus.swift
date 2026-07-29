//
//  BoothStatus.swift
//  TelephoneBoothOperatorMobile
//
//  Mirrors the `BoothStatus` and `BoothState` schemas from the operator
//  OpenAPI spec.
//

import Foundation

public enum BoothState: Codable, Sendable, Hashable {
    case idle
    case dialTone
    case dialing
    case playingQuestion
    case beep
    case recording
    case uploading
    case playingMessage
    case playingInstructions
    case callUnavailable
    case error
    case unknown(String)

    // MARK: - Known cases (for iteration where needed)

    public static let knownCases: [BoothState] = [
        .idle, .dialTone, .dialing, .playingQuestion, .beep,
        .recording, .uploading, .playingMessage, .playingInstructions, .callUnavailable, .error
    ]

    // MARK: - Raw value mapping

    public var rawValue: String {
        switch self {
        case .idle: return "idle"
        case .dialTone: return "dialTone"
        case .dialing: return "dialing"
        case .playingQuestion: return "playingQuestion"
        case .beep: return "beep"
        case .recording: return "recording"
        case .uploading: return "uploading"
        case .playingMessage: return "playingMessage"
        case .playingInstructions: return "playingInstructions"
        case .callUnavailable: return "callUnavailable"
        case .error: return "error"
        case .unknown(let value): return value
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    public init(rawValue: String) {
        switch rawValue {
        case "idle": self = .idle
        case "dialTone": self = .dialTone
        case "dialing": self = .dialing
        case "playingQuestion": self = .playingQuestion
        case "beep": self = .beep
        case "recording": self = .recording
        case "uploading": self = .uploading
        case "playingMessage": self = .playingMessage
        case "playingInstructions": self = .playingInstructions
        case "callUnavailable": self = .callUnavailable
        case "error": self = .error
        default: self = .unknown(rawValue)
        }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // MARK: - Helpers

    /// Whether this state represents an actively-running call.
    public var isCallActive: Bool {
        switch self {
        case .dialing, .playingQuestion, .beep, .recording, .uploading,
             .playingMessage, .playingInstructions, .callUnavailable:
            return true
        case .idle, .dialTone, .error, .unknown:
            return false
        }
    }
}

public struct BoothStatus: Codable, Sendable, Hashable {
    /// The operator's snapshot row id. Two runs of the same status can share a
    /// booth timestamp, so this is the only thing that reliably tells one row
    /// from another. Optional for operators that predate it; ids increase with
    /// insertion order, which is also how the operator breaks those ties.
    public let id: Int?
    public let state: BoothState
    public let updatedAt: Date
    public let currentQuestionId: UUID?
    public let currentMessageId: UUID?
    public let lastError: String?
    /// Whether the booth is running real Pi hardware, in-memory mocks, or
    /// the interactive simulator TUI. Nullable + optional for forward and
    /// backward compatibility with operators that haven't shipped PR #66
    /// yet.
    public let runtimeMode: RuntimeMode?
    /// When the booth first reported this status. The booth repeats its
    /// status on a heartbeat and the operator collapses identical reports
    /// into one snapshot spanning `firstSeenAt`...`updatedAt`. Optional for
    /// compatibility with operators that predate the collapsing behaviour.
    public let firstSeenAt: Date?
    /// How many identical booth reports were collapsed into this snapshot.
    public let repeatCount: Int?

    /// When the booth entered this status, falling back to the report time
    /// against an operator that doesn't collapse repeats.
    public var heldSince: Date { firstSeenAt ?? updatedAt }

    /// Short "how long has the booth been like this" label, e.g. `12m` or
    /// `1h 04m · 142 reports`. The report count is only appended when the
    /// operator actually collapsed repeats, so it stays out of the way for a
    /// status that was reported exactly once.
    public func heldForLabel(now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(heldSince)))
        let duration: String
        switch seconds {
        case ..<60:
            duration = "\(seconds)s"
        case ..<3600:
            duration = "\(seconds / 60)m"
        default:
            duration = String(format: "%dh %02dm", seconds / 3600, (seconds % 3600) / 60)
        }
        guard let repeatCount, repeatCount > 1 else { return duration }
        return "\(duration) · \(repeatCount) reports"
    }

    /// Whether two snapshots are the same collapsed run.
    ///
    /// The operator re-broadcasts a run's row on every booth heartbeat with a
    /// newer `updatedAt`, so a later frame supersedes an earlier one rather
    /// than joining it in the history. `updatedAt` can't tell them apart, and
    /// neither can `firstSeenAt` alone: a repeat that reaches the operator out
    /// of order widens the window backwards, so the same row can arrive with
    /// an earlier `firstSeenAt` than the copy already held. A run's window only
    /// ever grows, so two views of one run are identical statuses where one
    /// window contains the other.
    ///
    /// Containment rather than plain overlap matters when transitions share a
    /// timestamp: `idle [a, t]`, `recording [t, t]`, `idle [t, b]` leaves two
    /// idle windows touching at `t`, and they are separate runs.
    ///
    /// An operator that predates collapsing sends no window at all, and its
    /// rows really are distinct reports, so they never match here.
    public func isSameRun(as other: BoothStatus) -> Bool {
        // Ids are exact: two views of one row, or two rows that look alike.
        if let id, let otherId = other.id { return id == otherId }
        guard let start = firstSeenAt, let otherStart = other.firstSeenAt else { return false }
        guard state == other.state,
              currentQuestionId == other.currentQuestionId,
              currentMessageId == other.currentMessageId,
              lastError == other.lastError,
              runtimeMode == other.runtimeMode
        else { return false }
        return (start <= otherStart && updatedAt >= other.updatedAt)
            || (otherStart <= start && other.updatedAt >= updatedAt)
    }

    /// Whether both report the same booth status, ignoring when they landed.
    public func isRepeat(of other: BoothStatus) -> Bool {
        state == other.state
            && currentQuestionId == other.currentQuestionId
            && currentMessageId == other.currentMessageId
            && lastError == other.lastError
            && runtimeMode == other.runtimeMode
    }

    /// The same run, reported again at `time` with `count` reports behind it.
    public func reported(at time: Date, repeatCount count: Int?) -> BoothStatus {
        BoothStatus(
            id: id,
            state: state,
            updatedAt: time,
            currentQuestionId: currentQuestionId,
            currentMessageId: currentMessageId,
            lastError: lastError,
            runtimeMode: runtimeMode,
            firstSeenAt: firstSeenAt,
            repeatCount: count
        )
    }

    public init(
        id: Int? = nil,
        state: BoothState,
        updatedAt: Date,
        currentQuestionId: UUID? = nil,
        currentMessageId: UUID? = nil,
        lastError: String? = nil,
        runtimeMode: RuntimeMode? = nil,
        firstSeenAt: Date? = nil,
        repeatCount: Int? = nil
    ) {
        self.id = id
        self.state = state
        self.updatedAt = updatedAt
        self.currentQuestionId = currentQuestionId
        self.currentMessageId = currentMessageId
        self.lastError = lastError
        self.runtimeMode = runtimeMode
        self.firstSeenAt = firstSeenAt
        self.repeatCount = repeatCount
    }
}

public extension Array where Element == BoothStatus {
    /// Fold adjacent reports of one status into a single run for display.
    ///
    /// The operator collapses on write, but rows recorded before it did are
    /// one per heartbeat, so an old idle stretch still arrives as hundreds of
    /// identical entries. Folding them here keeps the chart and the history
    /// reading one entry per status whatever the rows behind it look like.
    func collapsingRepeats() -> [BoothStatus] {
        reduce(into: [BoothStatus]()) { runs, item in
            guard let last = runs.last, last.isRepeat(of: item) else {
                runs.append(item)
                return
            }
            runs[runs.count - 1] = BoothStatus(
                id: last.id ?? item.id,
                state: last.state,
                updatedAt: Swift.max(last.updatedAt, item.updatedAt),
                currentQuestionId: last.currentQuestionId,
                currentMessageId: last.currentMessageId,
                lastError: last.lastError,
                runtimeMode: last.runtimeMode,
                firstSeenAt: Swift.min(last.heldSince, item.heldSince),
                repeatCount: (last.repeatCount ?? 1) + (item.repeatCount ?? 1)
            )
        }
    }
}
