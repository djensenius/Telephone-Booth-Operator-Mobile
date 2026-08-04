//
//  MessageRequests.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

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
    public let text: String
    public let language: String?
    public let model: String?
    public let processDownstream: Bool

    public init(
        text: String,
        language: String?,
        model: String?,
        processDownstream: Bool = false,
        expectedLatestTranscriptionId: String?
    ) {
        self.expectedLatestTranscriptionId = Self.trimmed(expectedLatestTranscriptionId)
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = Self.trimmed(language)
        self.model = Self.trimmed(model)
        self.processDownstream = processDownstream
    }

    private enum CodingKeys: String, CodingKey {
        case expectedLatestTranscriptionId
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
}

public struct MessageTranslationRequest: Codable, Sendable, Equatable {
    public let transcriptionId: String?
    public let expectedTranscriptionId: String?
    public let translatedText: String
    public let translatedLanguage: String?
    public let model: String?

    public init(
        transcriptionId: String? = nil,
        expectedTranscriptionId: String? = nil,
        translatedText: String,
        translatedLanguage: String? = "en",
        model: String? = nil
    ) {
        self.transcriptionId = Self.trimmed(transcriptionId)
        self.expectedTranscriptionId = Self.trimmed(expectedTranscriptionId)
        self.translatedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = translatedLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.translatedLanguage = language?.isEmpty == false ? language : nil
        self.model = Self.trimmed(model)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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
