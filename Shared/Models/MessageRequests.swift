// swiftlint:disable file_length
//
//  MessageRequests.swift
//  TelephoneBoothOperatorMobile
//

import CryptoKit
import Foundation

public enum ReviewTextSnapshot {
    private static let ecmaScriptTrimCharacters = CharacterSet(
        charactersIn: "\u{0009}\u{000B}\u{000C}\u{0020}\u{00A0}\u{1680}"
            + "\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}"
            + "\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}"
            + "\u{FEFF}\u{000A}\u{000D}\u{2028}\u{2029}"
    )

    public static func sha256(_ value: String?) -> String? {
        guard let value else { return nil }
        let canonical = value.trimmingCharacters(in: ecmaScriptTrimCharacters)
        guard !canonical.isEmpty else { return nil }
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public static func transcriptionSHA256(status: TranscriptionStatus?, text: String?) -> String? {
        guard let status else { return nil }
        let canonicalText = text?.trimmingCharacters(in: ecmaScriptTrimCharacters) ?? ""
        return SHA256.hash(data: Data("\(status.rawValue)\n\(canonicalText)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public extension Transcription {
    var translationSnapshotText: String? {
        translationStatus == .succeeded ? translatedText : nil
    }
}

public struct MessageDecisionRequest: Codable, Sendable, Equatable {
    public let decision: MessageDecision
    public let notes: String?

    public init(decision: MessageDecision, notes: String? = nil) {
        self.decision = decision
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}

public struct MessageTranscriptionRequest: Codable, Sendable, Equatable {
    public let expectedLatestTranscriptionId: String?
    public let expectedLatestTranscriptionSha256: String?
    public let text: String
    public let language: String?
    public let model: String?
    public let processDownstream: Bool

    public init(
        text: String,
        language: String?,
        model: String?,
        processDownstream: Bool = false,
        expectedLatestTranscriptionId: String?,
        expectedLatestTranscriptionSha256: String?
    ) {
        self.expectedLatestTranscriptionId = Self.trimmed(expectedLatestTranscriptionId)
        self.expectedLatestTranscriptionSha256 = Self.normalizedSHA256(expectedLatestTranscriptionSha256)
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = Self.trimmed(language)
        self.model = Self.trimmed(model)
        self.processDownstream = processDownstream
    }

    private enum CodingKeys: String, CodingKey {
        case expectedLatestTranscriptionId
        case expectedLatestTranscriptionSha256
        case text
        case language
        case model
        case processDownstream
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let expectedLatestTranscriptionId {
            try container.encode(expectedLatestTranscriptionId, forKey: .expectedLatestTranscriptionId)
        } else {
            try container.encodeNil(forKey: .expectedLatestTranscriptionId)
        }
        if let expectedLatestTranscriptionSha256 {
            try container.encode(expectedLatestTranscriptionSha256, forKey: .expectedLatestTranscriptionSha256)
        } else {
            try container.encodeNil(forKey: .expectedLatestTranscriptionSha256)
        }
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encode(processDownstream, forKey: .processDownstream)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedSHA256(_ value: String?) -> String? {
        guard let value = trimmed(value)?.lowercased(),
              value.count == 64,
              value.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return value
    }
}

public struct MessageTranslationRequest: Codable, Sendable, Equatable {
    public let transcriptionId: String?
    public let expectedTranscriptionId: String?
    public let expectedTranslationSha256: String?
    public let translatedText: String
    public let translatedLanguage: String?
    public let model: String?

    public init(
        transcriptionId: String? = nil,
        expectedTranscriptionId: String? = nil,
        expectedTranslationSha256: String?,
        translatedText: String,
        translatedLanguage: String? = "en",
        model: String? = nil
    ) {
        self.transcriptionId = Self.trimmed(transcriptionId)
        self.expectedTranscriptionId = Self.trimmed(expectedTranscriptionId)
        self.expectedTranslationSha256 = Self.normalizedSHA256(expectedTranslationSha256)
        self.translatedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = translatedLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.translatedLanguage = language?.isEmpty == false ? language : nil
        self.model = Self.trimmed(model)
    }

    private enum CodingKeys: String, CodingKey {
        case transcriptionId
        case expectedTranscriptionId
        case expectedTranslationSha256
        case translatedText
        case translatedLanguage
        case model
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(transcriptionId, forKey: .transcriptionId)
        try container.encodeIfPresent(expectedTranscriptionId, forKey: .expectedTranscriptionId)
        if let expectedTranslationSha256 {
            try container.encode(expectedTranslationSha256, forKey: .expectedTranslationSha256)
        } else {
            try container.encodeNil(forKey: .expectedTranslationSha256)
        }
        try container.encode(translatedText, forKey: .translatedText)
        try container.encodeIfPresent(translatedLanguage, forKey: .translatedLanguage)
        try container.encodeIfPresent(model, forKey: .model)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedSHA256(_ value: String?) -> String? {
        guard let value = trimmed(value)?.lowercased(),
              value.count == 64,
              value.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return value
    }
}

public struct MessageModerationRequest: Codable, Sendable, Equatable {
    public let transcriptionId: String?
    public let inputSha256: String?
    public let flagged: Bool
    public let recommendation: String
    public let maxScore: Double
    public let reasonSummary: String?
    public let model: String?

    public init(
        transcriptionId: String?,
        inputSha256: String? = nil,
        flagged: Bool,
        recommendation: ModerationRecommendation,
        maxScore: Double,
        reasonSummary: String? = nil,
        model: String?
    ) {
        self.transcriptionId = Self.trimmed(transcriptionId)
        self.inputSha256 = Self.normalizedSHA256(inputSha256)
        self.flagged = flagged
        self.recommendation = recommendation.rawValue
        self.maxScore = min(max(maxScore.isFinite ? maxScore : 0, 0), 1)
        self.reasonSummary = Self.trimmed(reasonSummary)
        self.model = Self.trimmed(model)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedSHA256(_ value: String?) -> String? {
        guard let value = trimmed(value)?.lowercased(),
              value.count == 64,
              value.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return value
    }
}

public enum MessageProcessingStep: Codable, Sendable, Hashable {
    case transcription
    case translation
    case moderation
    case review
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .transcription: return "transcription"
        case .translation: return "translation"
        case .moderation: return "moderation"
        case .review: return "review"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "transcription": self = .transcription
        case "translation": self = .translation
        case "moderation": self = .moderation
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

    public var displayName: String {
        switch self {
        case .transcription: return "Transcribing"
        case .translation: return "Translating"
        case .moderation: return "Reviewing"
        case .review: return "Classifying silence"
        case .unknown(let value): return value
        }
    }
}

public struct MessageProcessingClaimRequest: Codable, Sendable, Equatable {
    public let capabilities: [MessageProcessingStep]
    public let leaseSeconds: Int

    public init(
        capabilities: [MessageProcessingStep] = [.transcription, .translation, .moderation, .review],
        leaseSeconds: Int = 300
    ) {
        self.capabilities = capabilities
        self.leaseSeconds = min(max(leaseSeconds, 30), 900)
    }
}

public struct MessageProcessingClaim: Codable, Sendable, Equatable {
    public let message: Message
    public let needs: [MessageProcessingStep]
    public let leaseToken: String
    public let leaseExpiresAt: Date
    public let defaultTranscriptionLanguage: String?

    public init(
        message: Message,
        needs: [MessageProcessingStep],
        leaseToken: String,
        leaseExpiresAt: Date,
        defaultTranscriptionLanguage: String?
    ) {
        self.message = message
        self.needs = needs
        self.leaseToken = leaseToken
        self.leaseExpiresAt = leaseExpiresAt
        self.defaultTranscriptionLanguage = defaultTranscriptionLanguage
    }
}

public struct MessageProcessingClaimResponse: Codable, Sendable, Equatable {
    public let claim: MessageProcessingClaim?

    public init(claim: MessageProcessingClaim?) {
        self.claim = claim
    }
}

public struct MessageProcessingSummary: Codable, Sendable, Equatable {
    public struct Needs: Codable, Sendable, Equatable {
        public let transcription: Int
        public let translation: Int
        public let moderation: Int
        public let review: Int

        public init(transcription: Int, translation: Int, moderation: Int, review: Int) {
            self.transcription = transcription
            self.translation = translation
            self.moderation = moderation
            self.review = review
        }

        public var total: Int {
            transcription + translation + moderation + review
        }
    }

    public let queued: Int
    public let leased: Int
    public let terminal: Int
    public let needs: Needs
    public let generatedAt: Date

    public init(queued: Int, leased: Int, terminal: Int, needs: Needs, generatedAt: Date) {
        self.queued = queued
        self.leased = leased
        self.terminal = terminal
        self.needs = needs
        self.generatedAt = generatedAt
    }
}

public struct MessageProcessingTranscriptionResult: Codable, Sendable, Equatable {
    public let expectedLatestTranscriptionId: String?
    public let expectedLatestTranscriptionSha256: String?
    public let text: String
    public let language: String?
    public let model: String?

    public init(
        expectedLatestTranscriptionId: String?,
        expectedLatestTranscriptionSha256: String?,
        text: String,
        language: String?,
        model: String?
    ) {
        self.expectedLatestTranscriptionId = expectedLatestTranscriptionId
        self.expectedLatestTranscriptionSha256 = expectedLatestTranscriptionSha256
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case expectedLatestTranscriptionId
        case expectedLatestTranscriptionSha256
        case text
        case language
        case model
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let expectedLatestTranscriptionId {
            try container.encode(expectedLatestTranscriptionId, forKey: .expectedLatestTranscriptionId)
        } else {
            try container.encodeNil(forKey: .expectedLatestTranscriptionId)
        }
        if let expectedLatestTranscriptionSha256 {
            try container.encode(expectedLatestTranscriptionSha256, forKey: .expectedLatestTranscriptionSha256)
        } else {
            try container.encodeNil(forKey: .expectedLatestTranscriptionSha256)
        }
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(model, forKey: .model)
    }
}

public struct MessageProcessingTranslationResult: Codable, Sendable, Equatable {
    public let transcriptionId: String?
    public let expectedTranslationSha256: String?
    public let translatedText: String
    public let translatedLanguage: String?
    public let model: String?

    public init(
        transcriptionId: String?,
        expectedTranslationSha256: String?,
        translatedText: String,
        translatedLanguage: String?,
        model: String?
    ) {
        self.transcriptionId = transcriptionId
        self.expectedTranslationSha256 = expectedTranslationSha256
        self.translatedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.translatedLanguage = translatedLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case transcriptionId
        case expectedTranslationSha256
        case translatedText
        case translatedLanguage
        case model
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(transcriptionId, forKey: .transcriptionId)
        if let expectedTranslationSha256 {
            try container.encode(expectedTranslationSha256, forKey: .expectedTranslationSha256)
        } else {
            try container.encodeNil(forKey: .expectedTranslationSha256)
        }
        try container.encode(translatedText, forKey: .translatedText)
        try container.encodeIfPresent(translatedLanguage, forKey: .translatedLanguage)
        try container.encodeIfPresent(model, forKey: .model)
    }
}

public struct MessageProcessingModerationResult: Codable, Sendable, Equatable {
    public let inputSha256: String?
    public let flagged: Bool
    public let recommendation: ModerationRecommendation
    public let maxScore: Double
    public let categories: [String: Double]?
    public let reasonSummary: String?
    public let model: String?

    public init(
        inputSha256: String?,
        flagged: Bool,
        recommendation: ModerationRecommendation,
        maxScore: Double,
        categories: [String: Double]? = nil,
        reasonSummary: String? = nil,
        model: String?
    ) {
        self.inputSha256 = inputSha256
        self.flagged = flagged
        self.recommendation = recommendation
        self.maxScore = min(max(maxScore.isFinite ? maxScore : 0, 0), 1)
        self.categories = categories
        self.reasonSummary = reasonSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct MessageProcessingReviewResult: Codable, Sendable, Equatable {
    public let classification: MessageReviewClassification
    public let recommendation: MessageReviewRecommendation

    public init(
        classification: MessageReviewClassification,
        recommendation: MessageReviewRecommendation
    ) {
        self.classification = classification
        self.recommendation = recommendation
    }
}

public struct MessageProcessingCompleteRequest: Codable, Sendable, Equatable {
    public let leaseToken: String
    public let transcription: MessageProcessingTranscriptionResult?
    public let translation: MessageProcessingTranslationResult?
    public let moderation: MessageProcessingModerationResult?
    public let review: MessageProcessingReviewResult?

    public init(
        leaseToken: String,
        transcription: MessageProcessingTranscriptionResult? = nil,
        translation: MessageProcessingTranslationResult? = nil,
        moderation: MessageProcessingModerationResult? = nil,
        review: MessageProcessingReviewResult? = nil
    ) {
        self.leaseToken = leaseToken
        self.transcription = transcription
        self.translation = translation
        self.moderation = moderation
        self.review = review
    }
}

public struct MessageProcessingCompleteResponse: Codable, Sendable, Equatable {
    public let message: Message
    public let needs: [MessageProcessingStep]

    public init(message: Message, needs: [MessageProcessingStep]) {
        self.message = message
        self.needs = needs
    }
}

public struct MessageProcessingHeartbeatRequest: Codable, Sendable, Equatable {
    public let leaseToken: String
    public let leaseSeconds: Int

    public init(leaseToken: String, leaseSeconds: Int = 300) {
        self.leaseToken = leaseToken
        self.leaseSeconds = min(max(leaseSeconds, 30), 900)
    }
}

public struct MessageProcessingLeaseTokenRequest: Codable, Sendable, Equatable {
    public let leaseToken: String

    public init(leaseToken: String) {
        self.leaseToken = leaseToken
    }
}

public struct MessageProcessingFailRequest: Codable, Sendable, Equatable {
    public let leaseToken: String
    public let errorCode: String
    public let errorMessage: String?

    public init(leaseToken: String, errorCode: String, errorMessage: String? = nil) {
        self.leaseToken = leaseToken
        self.errorCode = errorCode
        self.errorMessage = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct MessageProcessingHeartbeatResponse: Codable, Sendable, Equatable {
    public let succeeded: Bool
    public let leaseExpiresAt: Date

    enum CodingKeys: String, CodingKey {
        case succeeded = "ok"
        case leaseExpiresAt
    }
}

public struct MessageProcessingFailResponse: Codable, Sendable, Equatable {
    public let succeeded: Bool
    public let terminal: Bool

    enum CodingKeys: String, CodingKey {
        case succeeded = "ok"
        case terminal
    }
}
