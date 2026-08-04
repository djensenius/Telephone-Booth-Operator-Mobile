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
    case push
    case onDevice
    case disabled
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .openai: return "openai"
        case .macApp: return "mac_app"
        case .push: return "push"
        case .onDevice: return "on_device"
        case .disabled: return "disabled"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "openai": self = .openai
        case "mac_app": self = .macApp
        case "push": self = .push
        case "on_device": self = .onDevice
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
        case .push: return "Push worker"
        case .onDevice: return "On device"
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
    public let translationStatus: TranscriptionStatus?
    public let translatedText: String?
    public let translatedLanguage: String?
    public let translationProvider: AiProvider?
    public let translationModel: String?
    public let translationError: String?
    public let translationLatencyMs: Int?
    public let translationCompletedAt: Date?

    public init(
        id: String,
        messageId: String,
        provider: AiProvider,
        model: String?,
        status: TranscriptionStatus,
        text: String?,
        language: String?,
        durationMs: Int?,
        latencyMs: Int?,
        error: String?,
        requestedById: String?,
        createdAt: Date,
        completedAt: Date?,
        translationStatus: TranscriptionStatus? = nil,
        translatedText: String? = nil,
        translatedLanguage: String? = nil,
        translationProvider: AiProvider? = nil,
        translationModel: String? = nil,
        translationError: String? = nil,
        translationLatencyMs: Int? = nil,
        translationCompletedAt: Date? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.provider = provider
        self.model = model
        self.status = status
        self.text = text
        self.language = language
        self.durationMs = durationMs
        self.latencyMs = latencyMs
        self.error = error
        self.requestedById = requestedById
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.translationStatus = translationStatus
        self.translatedText = translatedText
        self.translatedLanguage = translatedLanguage
        self.translationProvider = translationProvider
        self.translationModel = translationModel
        self.translationError = translationError
        self.translationLatencyMs = translationLatencyMs
        self.translationCompletedAt = translationCompletedAt
    }

    public var completedTranslation: String? {
        guard translationStatus == .succeeded,
              let translatedText,
              !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return translatedText
    }
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
    public let requestedById: String?
    public let createdAt: Date
    public let completedAt: Date?

    public init(
        id: String,
        messageId: String,
        transcriptionId: String?,
        provider: AiProvider,
        model: String?,
        status: TranscriptionStatus,
        flagged: Bool?,
        recommendation: ModerationRecommendation?,
        maxScore: Double?,
        categories: [String: Double]?,
        reasonSummary: String?,
        latencyMs: Int?,
        error: String?,
        requestedById: String? = nil,
        createdAt: Date,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.transcriptionId = transcriptionId
        self.provider = provider
        self.model = model
        self.status = status
        self.flagged = flagged
        self.recommendation = recommendation
        self.maxScore = maxScore
        self.categories = categories
        self.reasonSummary = reasonSummary
        self.latencyMs = latencyMs
        self.error = error
        self.requestedById = requestedById
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
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

/// A human moderation decision. The AI moderation result is only ever an
/// advisory suggestion — approving or rejecting a message is always an explicit
/// operator action recorded server-side against the acting operator.
public enum MessageDecision: String, Codable, Sendable, Hashable {
    case approve
    case reject
}

extension Message {
    public var bestDisplayText: String? {
        if let translation = latestTranscription?.completedTranslation {
            return translation
        }
        guard let transcript = latestTranscription?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !transcript.isEmpty else {
            return nil
        }
        return transcript
    }

    /// Returns a copy of the message reflecting a human approve/reject
    /// decision. Used to model the server response in demo mode.
    public func applyingDecision(_ decision: MessageDecision, notes: String?) -> Message {
        Message(
            id: id,
            status: decision == .approve ? .approved : .rejected,
            questionId: questionId,
            notes: notes ?? self.notes,
            createdAt: createdAt,
            receivedAt: receivedAt,
            audio: audio,
            latestTranscription: latestTranscription,
            latestModeration: latestModeration
        )
    }

    public func replacingLatestTranscription(_ transcription: Transcription) -> Message {
        let previousHash = ReviewTextSnapshot.sha256(latestTranscription?.translationSnapshotText)
            ?? ReviewTextSnapshot.sha256(latestTranscription?.text)
        let updatedHash = ReviewTextSnapshot.sha256(transcription.translationSnapshotText)
            ?? ReviewTextSnapshot.sha256(transcription.text)
        let textChanged = previousHash != updatedHash
        let moderation = latestModeration.flatMap { existing -> Moderation? in
            guard !textChanged else { return nil }
            guard let owner = existing.transcriptionId else { return existing }
            return owner == transcription.id ? existing : nil
        }
        return Message(
            id: id,
            status: status,
            questionId: questionId,
            notes: notes,
            createdAt: createdAt,
            receivedAt: receivedAt,
            audio: audio,
            latestTranscription: transcription,
            latestModeration: moderation
        )
    }

    public func replacingLatestModeration(_ moderation: Moderation) -> Message {
        Message(
            id: id,
            status: status,
            questionId: questionId,
            notes: notes,
            createdAt: createdAt,
            receivedAt: receivedAt,
            audio: audio,
            latestTranscription: latestTranscription,
            latestModeration: moderation
        )
    }
}
