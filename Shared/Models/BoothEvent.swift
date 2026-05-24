//
//  BoothEvent.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public enum BoothEventType: String, Codable, Sendable, CaseIterable {
    case callStarted = "call_started"
    case callEnded = "call_ended"
    case digitDialed = "digit_dialed"
    case stateTransition = "state_transition"
    case recordingStarted = "recording_started"
    case recordingStopped = "recording_stopped"
    case uploadStarted = "upload_started"
    case uploadCompleted = "upload_completed"
    case uploadFailed = "upload_failed"
    case gpioEdge = "gpio_edge"
    case audioDeviceChange = "audio_device_change"
    case operatorRequest = "operator_request"
    case operatorResponse = "operator_response"
    case error
    case log
    case systemSample = "system_sample"

    public var displayName: String {
        rawValue
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

public struct BoothEventRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let eventId: String
    public let boothId: String
    public let bootId: String
    public let type: BoothEventType
    public let occurredAt: Date
    public let receivedAt: Date
    public let sessionId: String?
    public let recordingId: String?
}

public struct CallSessionDetail: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let boothId: String
    public let bootId: String
    public let startedAt: Date
    public let endedAt: Date?
    public let digitsDialed: String?
    public let outcome: CallOutcome?
    public let recordingId: String?
    public let durationMs: Int?
    public let events: [BoothEventRecord]

    public var asSession: CallSession {
        CallSession(
            id: id,
            boothId: boothId,
            bootId: bootId,
            startedAt: startedAt,
            endedAt: endedAt,
            digitsDialed: digitsDialed,
            outcome: outcome,
            recordingId: recordingId,
            durationMs: durationMs
        )
    }
}
