//
//  Message.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public enum MessageStatus: String, Codable, Sendable, CaseIterable {
    case uploading
    case received
    case pending
    case approved
    case rejected

    public var displayName: String { rawValue.capitalized }
}

public enum AiProvider: String, Codable, Sendable, CaseIterable {
    case openai
    case macApp = "mac_app"
    case disabled

    public var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .macApp: return "Mac app"
        case .disabled: return "Disabled"
        }
    }
}

public enum TranscriptionStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case succeeded
    case failed

    public var displayName: String { rawValue.capitalized }
}

public enum ModerationRecommendation: String, Codable, Sendable, CaseIterable {
    case approve
    case review
    case reject

    public var displayName: String { rawValue.capitalized }
}

public struct AudioRef: Codable, Sendable, Equatable {
    public let url: URL
    public let sha256: String
    public let durationMs: Int?

    public init(url: URL, sha256: String, durationMs: Int?) {
        self.url = url
        self.sha256 = sha256
        self.durationMs = durationMs
    }
}

public struct Transcription: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let messageId: String
    public let provider: AiProvider
    public let model: String?
    public let status: TranscriptionStatus
    public let text: String?
    public let language: String?
    public let durationMs: Int?
    public let latencyMs: Int?
    public let error: String?
    public let requestedById: String?
    public let createdAt: Date
    public let completedAt: Date?
}

public struct TranscriptionList: Codable, Sendable, Equatable {
    public let items: [Transcription]

    public init(items: [Transcription]) {
        self.items = items
    }
}

public struct Moderation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let messageId: String
    public let transcriptionId: String?
    public let provider: AiProvider
    public let model: String?
    public let status: TranscriptionStatus
    public let flagged: Bool?
    public let recommendation: ModerationRecommendation?
    public let maxScore: Double?
    public let categories: [String: Double]?
    public let reasonSummary: String?
    public let latencyMs: Int?
    public let error: String?
    public let createdAt: Date
}

public struct Message: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let status: MessageStatus
    public let questionId: String?
    public let notes: String?
    public let createdAt: Date
    public let receivedAt: Date?
    public let audio: AudioRef
    public let latestTranscription: Transcription?
    public let latestModeration: Moderation?
}

public struct MessageList: Codable, Sendable, Equatable {
    public let items: [Message]

    public init(items: [Message]) {
        self.items = items
    }
}
