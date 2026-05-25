//
//  BoothEvent.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public enum BoothEventType: Codable, Sendable, Hashable {
    case callStarted
    case callEnded
    case digitDialed
    case stateTransition
    case recordingStarted
    case recordingStopped
    case uploadStarted
    case uploadCompleted
    case uploadFailed
    case gpioEdge
    case audioDeviceChange
    case operatorRequest
    case operatorResponse
    case error
    case log
    case systemSample
    case unknown(String)

    public static let knownCases: [BoothEventType] = [
        .callStarted, .callEnded, .digitDialed, .stateTransition,
        .recordingStarted, .recordingStopped, .uploadStarted, .uploadCompleted,
        .uploadFailed, .gpioEdge, .audioDeviceChange, .operatorRequest,
        .operatorResponse, .error, .log, .systemSample
    ]

    // MARK: - Raw value mapping

    public var rawValue: String {
        switch self {
        case .callStarted: return "call_started"
        case .callEnded: return "call_ended"
        case .digitDialed: return "digit_dialed"
        case .stateTransition: return "state_transition"
        case .recordingStarted: return "recording_started"
        case .recordingStopped: return "recording_stopped"
        case .uploadStarted: return "upload_started"
        case .uploadCompleted: return "upload_completed"
        case .uploadFailed: return "upload_failed"
        case .gpioEdge: return "gpio_edge"
        case .audioDeviceChange: return "audio_device_change"
        case .operatorRequest: return "operator_request"
        case .operatorResponse: return "operator_response"
        case .error: return "error"
        case .log: return "log"
        case .systemSample: return "system_sample"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "call_started": self = .callStarted
        case "call_ended": self = .callEnded
        case "digit_dialed": self = .digitDialed
        case "state_transition": self = .stateTransition
        case "recording_started": self = .recordingStarted
        case "recording_stopped": self = .recordingStopped
        case "upload_started": self = .uploadStarted
        case "upload_completed": self = .uploadCompleted
        case "upload_failed": self = .uploadFailed
        case "gpio_edge": self = .gpioEdge
        case "audio_device_change": self = .audioDeviceChange
        case "operator_request": self = .operatorRequest
        case "operator_response": self = .operatorResponse
        case "error": self = .error
        case "log": self = .log
        case "system_sample": self = .systemSample
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

public struct EventList: Codable, Sendable, Equatable {
    public let items: [BoothEventRecord]
    public let nextCursor: String?

    public init(items: [BoothEventRecord], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
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
