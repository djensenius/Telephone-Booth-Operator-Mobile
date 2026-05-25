//
//  Message.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public enum MessageStatus: Codable, Sendable, Hashable {
    case uploading
    case received
    case pending
    case approved
    case rejected
    case unknown(String)

    public static let knownCases: [MessageStatus] = [
        .uploading, .received, .pending, .approved, .rejected
    ]

    public var rawValue: String {
        switch self {
        case .uploading: return "uploading"
        case .received: return "received"
        case .pending: return "pending"
        case .approved: return "approved"
        case .rejected: return "rejected"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "uploading": self = .uploading
        case "received": self = .received
        case "pending": self = .pending
        case "approved": self = .approved
        case "rejected": self = .rejected
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

    public var displayName: String { rawValue.capitalized }
}

public enum AiProvider: Codable, Sendable, Hashable {
    case openai
    case macApp
    case disabled
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .openai: return "openai"
        case .macApp: return "mac_app"
        case .disabled: return "disabled"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "openai": self = .openai
        case "mac_app": self = .macApp
        case "disabled": self = .disabled
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
        case .openai: return "OpenAI"
        case .macApp: return "Mac app"
        case .disabled: return "Disabled"
        case .unknown(let value): return value
        }
    }
}

public enum TranscriptionStatus: Codable, Sendable, Hashable {
    case pending
    case succeeded
    case failed
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .pending: return "pending"
        case .succeeded: return "succeeded"
        case .failed: return "failed"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "pending": self = .pending
        case "succeeded": self = .succeeded
        case "failed": self = .failed
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

    public var displayName: String { rawValue.capitalized }
}

public enum ModerationRecommendation: Codable, Sendable, Hashable {
    case approve
    case review
    case reject
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .approve: return "approve"
        case .review: return "review"
        case .reject: return "reject"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "approve": self = .approve
        case "review": self = .review
        case "reject": self = .reject
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
