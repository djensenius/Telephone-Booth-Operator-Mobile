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
        case .aborted: return "aborted"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "hung_up_before_dial": self = .hungUpBeforeDial
        case "hung_up_during_prompt": self = .hungUpDuringPrompt
        case "hung_up_during_recording": self = .hungUpDuringRecording
        case "hung_up_during_upload": self = .hungUpDuringUpload
        case "recording_completed": self = .recordingCompleted
        case "recording_failed": self = .recordingFailed
        case "upload_failed": self = .uploadFailed
        case "operator_error": self = .operatorError
        case "aborted": self = .aborted
        default: self = .unknown(rawValue)
        }
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
        case .aborted: return "Aborted"
        case .unknown(let value):
            return value
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }

    public var isSuccess: Bool { self == .recordingCompleted }
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

    public init(
        id: String,
        boothId: String,
        bootId: String,
        startedAt: Date,
        endedAt: Date?,
        digitsDialed: String?,
        outcome: CallOutcome?,
        recordingId: String?,
        durationMs: Int?
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
