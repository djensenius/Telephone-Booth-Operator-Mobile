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

    public init(
        state: BoothState,
        updatedAt: Date,
        currentQuestionId: UUID? = nil,
        currentMessageId: UUID? = nil,
        lastError: String? = nil,
        runtimeMode: RuntimeMode? = nil
    ) {
        self.state = state
        self.updatedAt = updatedAt
        self.currentQuestionId = currentQuestionId
        self.currentMessageId = currentMessageId
        self.lastError = lastError
        self.runtimeMode = runtimeMode
    }
}
