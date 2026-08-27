// swiftlint:disable file_length
//
//  Message.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public enum MessageTranslationLanguage {
    public static let targetLanguage = "en"

    public static func shouldTranslate(
        sourceLanguage: String?,
        targetLanguage: String = MessageTranslationLanguage.targetLanguage
    ) -> Bool {
        guard let sourceCode = primaryLanguageCode(sourceLanguage),
              let targetCode = primaryLanguageCode(targetLanguage) else {
            return true
        }
        return sourceCode != targetCode
    }

    private static func primaryLanguageCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let identifier = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              let code = Locale(identifier: identifier).language.languageCode?.identifier,
              (2...3).contains(code.count),
              code.unicodeScalars.allSatisfy({
                  (65...90).contains($0.value) || (97...122).contains($0.value)
              }) else {
            return nil
        }
        return code.lowercased()
    }
}

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

public enum MessageListFilter: String, CaseIterable, Identifiable, Sendable, Hashable {
    case all
    case review
    case approved
    case rejected

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .review: return "Review"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        }
    }

    /// The server accepts one message status per request. Review must merge
    /// both pre-decision states so recently received messages are actionable.
    public var requestedStatuses: [MessageStatus]? {
        switch self {
        case .all: return nil
        case .review: return [.received, .pending]
        case .approved: return [.approved]
        case .rejected: return [.rejected]
        }
    }

    public func includes(_ status: MessageStatus) -> Bool {
        switch self {
        case .all: return true
        case .review: return status == .received || status == .pending
        case .approved: return status == .approved
        case .rejected: return status == .rejected
        }
    }

    public func shouldDismissDetail(afterDecisionTo status: MessageStatus) -> Bool {
        !includes(status)
    }

    /// Accepts the legacy widget `received` value while making `review` the
    /// canonical route for the combined operator queue.
    public init?(deepLinkValue: String) {
        switch deepLinkValue.lowercased() {
        case "all": self = .all
        case "review", "received", "pending": self = .review
        case "approved": self = .approved
        case "rejected": self = .rejected
        default: return nil
        }
    }
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

public enum MessageReviewClassification: Codable, Sendable, Hashable {
    case likelyHangup
    case unclear
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .likelyHangup: return "likely_hangup"
        case .unclear: return "unclear"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "likely_hangup": self = .likelyHangup
        case "unclear": self = .unclear
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        try self.init(rawValue: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum MessageReviewRecommendation: Codable, Sendable, Hashable {
    case delete
    case review
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .delete: return "delete"
        case .review: return "review"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "delete": self = .delete
        case "review": self = .review
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        try self.init(rawValue: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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

    public var shouldDisplayTranslation: Bool {
        translationStatus != nil
            && MessageTranslationLanguage.shouldTranslate(
                sourceLanguage: language,
                targetLanguage: translatedLanguage ?? MessageTranslationLanguage.targetLanguage
            )
    }

    public var displayableTranslation: String? {
        shouldDisplayTranslation ? completedTranslation : nil
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
    public let installationId: String?
    public let questionId: String?
    public let notes: String?
    public let createdAt: Date
    public let receivedAt: Date?
    public let reviewClassification: MessageReviewClassification?
    public let reviewRecommendation: MessageReviewRecommendation?
    public let reviewClassifiedAt: Date?
    public let reviewClassifiedById: String?
    public let audio: AudioRef
    public let latestTranscription: Transcription?
    public let latestModeration: Moderation?

    public init(
        id: String,
        status: MessageStatus,
        installationId: String? = nil,
        questionId: String?,
        notes: String?,
        createdAt: Date,
        receivedAt: Date?,
        reviewClassification: MessageReviewClassification? = nil,
        reviewRecommendation: MessageReviewRecommendation? = nil,
        reviewClassifiedAt: Date? = nil,
        reviewClassifiedById: String? = nil,
        audio: AudioRef,
        latestTranscription: Transcription?,
        latestModeration: Moderation?
    ) {
        self.id = id
        self.status = status
        self.installationId = installationId
        self.questionId = questionId
        self.notes = notes
        self.createdAt = createdAt
        self.receivedAt = receivedAt
        self.reviewClassification = reviewClassification
        self.reviewRecommendation = reviewRecommendation
        self.reviewClassifiedAt = reviewClassifiedAt
        self.reviewClassifiedById = reviewClassifiedById
        self.audio = audio
        self.latestTranscription = latestTranscription
        self.latestModeration = latestModeration
    }
}

public struct MessageList: Codable, Sendable, Equatable {
    public let items: [Message]

    public init(items: [Message]) {
        self.items = items
    }
}

/// A human moderation decision. The moderation result is only ever an advisory
/// suggestion — approving or rejecting a message is always an explicit
/// operator action recorded server-side against the acting operator.
public enum MessageDecision: String, Codable, Sendable, Hashable {
    case approve
    case reject
}

extension Message {
    public var bestDisplayText: String? {
        if let translation = latestTranscription?.displayableTranslation {
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
            installationId: installationId,
            questionId: questionId,
            notes: notes ?? self.notes,
            createdAt: createdAt,
            receivedAt: receivedAt,
            reviewClassification: reviewClassification,
            reviewRecommendation: reviewRecommendation,
            reviewClassifiedAt: reviewClassifiedAt,
            reviewClassifiedById: reviewClassifiedById,
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
            installationId: installationId,
            questionId: questionId,
            notes: notes,
            createdAt: createdAt,
            receivedAt: receivedAt,
            reviewClassification: reviewClassification,
            reviewRecommendation: reviewRecommendation,
            reviewClassifiedAt: reviewClassifiedAt,
            reviewClassifiedById: reviewClassifiedById,
            audio: audio,
            latestTranscription: transcription,
            latestModeration: moderation
        )
    }

    public func replacingLatestModeration(_ moderation: Moderation) -> Message {
        Message(
            id: id,
            status: status,
            installationId: installationId,
            questionId: questionId,
            notes: notes,
            createdAt: createdAt,
            receivedAt: receivedAt,
            reviewClassification: reviewClassification,
            reviewRecommendation: reviewRecommendation,
            reviewClassifiedAt: reviewClassifiedAt,
            reviewClassifiedById: reviewClassifiedById,
            audio: audio,
            latestTranscription: latestTranscription,
            latestModeration: moderation
        )
    }

    public var recommendsPermanentDelete: Bool {
        reviewRecommendation == .delete
    }
}
