//
//  OnDeviceReviewTypes.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public protocol AudioTranscribing: Sendable {
    func transcribe(audioFileURL: URL, language: String?) async throws -> String
}

public struct TranslationResult: Sendable, Equatable {
    public let translatedText: String
    public let sourceLanguage: String?
    public let targetLanguage: String
    public let model: String
}

public protocol TextTranslating: Sendable {
    func translate(_ input: String, sourceLanguage: String?) async throws -> TranslationResult
}

public struct ModerationVerdict: Sendable, Equatable {
    public let flagged: Bool
    public let recommendation: ModerationRecommendation
    public let maxScore: Double
    public let model: String
}

public protocol TextModerating: Sendable {
    func moderate(_ input: String) async throws -> ModerationVerdict
}

public enum OnDeviceServiceError: Error, Sendable, Equatable, LocalizedError {
    case badRequest(String)
    case unauthorized(String)
    case timeout(String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .badRequest(let message),
             .unauthorized(let message),
             .timeout(let message),
             .unavailable(let message):
            return message
        }
    }
}

public enum PromptSafety {
    public static func sanitizeForDelimitedPrompt(_ input: String) -> String {
        input
            .replacingOccurrences(of: "<<<TEXT>>>", with: "<\u{200B}<\u{200B}<TEXT>\u{200B}>\u{200B}>")
            .replacingOccurrences(of: "<<<END>>>", with: "<\u{200B}<\u{200B}<END>\u{200B}>\u{200B}>")
    }

    public static func normalizedLanguageTag(_ tag: String?) -> String? {
        guard let tag else { return nil }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 35 else { return nil }

        var subtags = trimmed.split(separator: "-", omittingEmptySubsequences: false)[...]
        guard let language = subtags.popFirst(),
              (2...3).contains(language.count),
              language.allSatisfy(\.isAsciiLetter) else {
            return nil
        }
        if let next = subtags.first, next.count == 4, next.allSatisfy(\.isAsciiLetter) {
            subtags.removeFirst()
        }
        if let next = subtags.first,
           next.count == 2 && next.allSatisfy(\.isAsciiLetter)
            || next.count == 3 && next.allSatisfy(\.isAsciiDigit) {
            subtags.removeFirst()
        }
        consumeVariants(&subtags)
        guard consumeExtensions(&subtags), consumePrivateUse(&subtags) else { return nil }
        return trimmed
    }

    private static func consumeVariants(_ subtags: inout ArraySlice<Substring>) {
        while let variant = subtags.first {
            let longForm = (5...8).contains(variant.count)
                && variant.allSatisfy(\.isAsciiAlphanumeric)
            let digitForm = variant.count == 4
                && variant.first?.isAsciiDigit == true
                && variant.allSatisfy(\.isAsciiAlphanumeric)
            guard longForm || digitForm else { return }
            subtags.removeFirst()
        }
    }

    private static func consumeExtensions(_ subtags: inout ArraySlice<Substring>) -> Bool {
        while let singleton = subtags.first,
              singleton.count == 1,
              singleton.allSatisfy(\.isAsciiAlphanumeric),
              singleton.lowercased() != "x" {
            subtags.removeFirst()
            var hasExtensionSubtag = false
            while let extensionSubtag = subtags.first,
                  (2...8).contains(extensionSubtag.count),
                  extensionSubtag.allSatisfy(\.isAsciiAlphanumeric) {
                hasExtensionSubtag = true
                subtags.removeFirst()
            }
            guard hasExtensionSubtag else { return false }
        }
        return true
    }

    private static func consumePrivateUse(_ subtags: inout ArraySlice<Substring>) -> Bool {
        guard subtags.first?.lowercased() == "x" else { return subtags.isEmpty }
        subtags.removeFirst()
        guard !subtags.isEmpty else { return false }
        return subtags.allSatisfy {
            (1...8).contains($0.count) && $0.allSatisfy(\.isAsciiAlphanumeric)
        }
    }
}

public enum OnDeviceReviewLogic {
    public static func translation(
        text: String,
        detectedSource: String?,
        fallbackSource: String?,
        model: String
    ) -> TranslationResult {
        let detected = normalizedSource(detectedSource)
        let fallback = normalizedSource(fallbackSource)
        return TranslationResult(
            translatedText: normalizedTranslationText(text),
            sourceLanguage: (detected == "und" || detected == "unknown") ? fallback : detected ?? fallback,
            targetLanguage: "en",
            model: model
        )
    }

    public static func moderation(
        flagged: Bool,
        severityScore: Double,
        model: String
    ) -> ModerationVerdict {
        let score = min(max(severityScore.isFinite ? severityScore : 0, 0), 1)
        let recommendation: ModerationRecommendation
        if flagged {
            recommendation = .reject
        } else if score > 0.5 {
            recommendation = .review
        } else {
            recommendation = .approve
        }
        return ModerationVerdict(
            flagged: flagged,
            recommendation: recommendation,
            maxScore: score,
            model: model
        )
    }

    private static func normalizedSource(_ value: String?) -> String? {
        PromptSafety.normalizedLanguageTag(value)?.lowercased()
    }

    private static func normalizedTranslationText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if trimmed.hasPrefix("```"), trimmed.hasSuffix("```"),
           let firstLineBreak = trimmed.firstIndex(of: "\n") {
            let contentStart = trimmed.index(after: firstLineBreak)
            let contentEnd = trimmed.index(trimmed.endIndex, offsetBy: -3)
            candidate = String(trimmed[contentStart..<contentEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            candidate = trimmed
        }
        guard let data = candidate.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return trimmed
        }
        for key in ["translatedText", "translated_text", "message", "text"] {
            if let result = object[key] as? String {
                let normalized = result.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty { return normalized }
            }
        }
        return trimmed
    }
}

private extension Character {
    var isAsciiLetter: Bool { isASCII && isLetter }
    var isAsciiDigit: Bool { isASCII && isNumber }
    var isAsciiAlphanumeric: Bool { isAsciiLetter || isAsciiDigit }
}
