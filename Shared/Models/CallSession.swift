//
//  CallSession.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public enum CallOutcome: String, Codable, Sendable, CaseIterable {
    case hungUpBeforeDial = "hung_up_before_dial"
    case hungUpDuringPrompt = "hung_up_during_prompt"
    case hungUpDuringRecording = "hung_up_during_recording"
    case hungUpDuringUpload = "hung_up_during_upload"
    case recordingCompleted = "recording_completed"
    case recordingFailed = "recording_failed"
    case uploadFailed = "upload_failed"
    case operatorError = "operator_error"
    case aborted

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
