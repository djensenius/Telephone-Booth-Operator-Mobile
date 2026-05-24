//
//  BoothStatus.swift
//  TelephoneBoothOperatorMobile
//
//  Mirrors the `BoothStatus` and `BoothState` schemas from the operator
//  OpenAPI spec.
//

import Foundation

public enum BoothState: String, Codable, Sendable, CaseIterable {
    case idle
    case dialTone
    case dialing
    case playingQuestion
    case beep
    case recording
    case uploading
    case playingMessage
    case playingInstructions
    case error

    /// Whether this state represents an actively-running call.
    public var isCallActive: Bool {
        switch self {
        case .dialing, .playingQuestion, .beep, .recording, .uploading,
             .playingMessage, .playingInstructions:
            return true
        case .idle, .dialTone, .error:
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

    public init(
        state: BoothState,
        updatedAt: Date,
        currentQuestionId: UUID? = nil,
        currentMessageId: UUID? = nil,
        lastError: String? = nil
    ) {
        self.state = state
        self.updatedAt = updatedAt
        self.currentQuestionId = currentQuestionId
        self.currentMessageId = currentMessageId
        self.lastError = lastError
    }
}
