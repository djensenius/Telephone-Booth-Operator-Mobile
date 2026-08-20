//
//  CallSession.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public enum CallOutcome: Codable, Sendable, Hashable {
    case hungUpBeforeDial
    case hungUpDuringPrompt
    case hungUpDuringRecording
    case hungUpDuringUpload
    case recordingCompleted
    case recordingFailed
    case uploadFailed
    case operatorError
    case installationEnded
    case aborted
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .hungUpBeforeDial: return "hung_up_before_dial"
        case .hungUpDuringPrompt: return "hung_up_during_prompt"
        case .hungUpDuringRecording: return "hung_up_during_recording"
        case .hungUpDuringUpload: return "hung_up_during_upload"
        case .recordingCompleted: return "recording_completed"
        case .recordingFailed: return "recording_failed"
        case .uploadFailed: return "upload_failed"
        case .operatorError: return "operator_error"
        case .installationEnded: return "installation_ended"
        case .aborted: return "aborted"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        self = Self.knownCasesByRawValue[rawValue] ?? .unknown(rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayName: String {
        switch self {
        case .hungUpBeforeDial: return "Hung up before dial"
        case .hungUpDuringPrompt: return "Hung up during prompt"
        case .hungUpDuringRecording: return "Hung up during recording"
        case .hungUpDuringUpload: return "Hung up during upload"
        case .recordingCompleted: return "Recording completed"
        case .recordingFailed: return "Recording failed"
        case .uploadFailed: return "Upload failed"
        case .operatorError: return "Operator error"
        case .installationEnded: return "Installation ended"
        case .aborted: return "Aborted"
        case .unknown(let value):
            return value
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }

    public var isSuccess: Bool { self == .recordingCompleted }

    private static let knownCasesByRawValue: [String: CallOutcome] = [
        "hung_up_before_dial": .hungUpBeforeDial,
        "hung_up_during_prompt": .hungUpDuringPrompt,
        "hung_up_during_recording": .hungUpDuringRecording,
        "hung_up_during_upload": .hungUpDuringUpload,
        "recording_completed": .recordingCompleted,
        "recording_failed": .recordingFailed,
        "upload_failed": .uploadFailed,
        "operator_error": .operatorError,
        "installation_ended": .installationEnded,
        "aborted": .aborted
    ]
}

public struct CallSession: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let boothId: String
    public let bootId: String
    public let startedAt: Date
    public let endedAt: Date?
    public let digitsDialed: String?
    public let outcome: CallOutcome?
    public let recordingId: String?
    public let durationMs: Int?
    public let version: String?

    public init(
        id: String,
        boothId: String,
        bootId: String,
        startedAt: Date,
        endedAt: Date?,
        digitsDialed: String?,
        outcome: CallOutcome?,
        recordingId: String?,
        durationMs: Int?,
        version: String? = nil
    ) {
        self.id = id
        self.boothId = boothId
        self.bootId = bootId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.digitsDialed = digitsDialed
        self.outcome = outcome
        self.recordingId = recordingId
        self.durationMs = durationMs
        self.version = version
    }
}

public struct SessionListPage: Codable, Sendable, Equatable {
    public let items: [CallSession]
    public let nextCursor: String?

    public init(items: [CallSession], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

public struct CallsTodayPoint: Identifiable, Sendable, Equatable {
    public let id: Int
    public let date: Date
    public let count: Int
}

public struct CallsTodaySeries: Sendable, Equatable {
    public let points: [CallsTodayPoint]
    public let total: Int
    public let dayStartedAt: Date
    public let through: Date

    public init(
        sessions: [CallSession],
        dayStartedAt: Date,
        now: Date = Date()
    ) {
        let through = max(dayStartedAt, now)
        var seenIDs = Set<String>()
        let starts = sessions
            .filter {
                $0.startedAt >= dayStartedAt
                    && $0.startedAt <= through
                    && seenIDs.insert($0.id).inserted
            }
            .sorted {
                if $0.startedAt == $1.startedAt {
                    return $0.id < $1.id
                }
                return $0.startedAt < $1.startedAt
            }

        var values = [(date: dayStartedAt, count: 0)]
        for session in starts {
            let nextCount = values.last.map { $0.count + 1 } ?? 1
            if values.last?.date == session.startedAt {
                values[values.count - 1].count = nextCount
            } else {
                values.append((session.startedAt, nextCount))
            }
        }

        if values.last?.date != through {
            values.append((through, values.last?.count ?? 0))
        }

        self.points = values.enumerated().map { index, value in
            CallsTodayPoint(id: index, date: value.date, count: value.count)
        }
        self.total = starts.count
        self.dayStartedAt = dayStartedAt
        self.through = through
    }

    public var yAxisValues: [Int] {
        guard total > 0 else { return [0, 1] }
        let step = max(1, Int(ceil(Double(total) / 4)))
        var values = Array(stride(from: 0, through: total, by: step))
        if values.last != total {
            values.append(total)
        }
        return values
    }
}

struct CallsTodayPageAccumulator: Sendable {
    let dayStartedAt: Date
    let knownSessionIDs: Set<String>
    private(set) var sessions: [CallSession] = []

    init(dayStartedAt: Date, knownSessionIDs: Set<String> = []) {
        self.dayStartedAt = dayStartedAt
        self.knownSessionIDs = knownSessionIDs
    }

    mutating func append(_ page: SessionListPage) -> String? {
        sessions.append(contentsOf: page.items.filter { $0.startedAt >= dayStartedAt })
        let overlapsCachedSessions = page.items.contains {
            knownSessionIDs.contains($0.id)
        }
        guard
            !overlapsCachedSessions,
            let nextCursor = page.nextCursor,
            let oldestSession = page.items.last,
            oldestSession.startedAt >= dayStartedAt
        else {
            return nil
        }
        return nextCursor
    }

    var orderedSessions: [CallSession] {
        sessions.sorted {
            if $0.startedAt == $1.startedAt {
                return $0.id < $1.id
            }
            return $0.startedAt < $1.startedAt
        }
    }
}
