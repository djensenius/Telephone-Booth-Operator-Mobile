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
