//
//  OnDeviceReviewTypes.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public protocol AudioTranscribing: Sendable {
    func transcribe(
        audioFileURL: URL,
        language: String?
    ) async throws -> AudioTranscriptionResult
}

public enum AudioTranscriptionResult: Sendable, Equatable {
    case speech(String)
    case noSpeech
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
    public static func noSpeechReview(durationMs: Int?) -> MessageProcessingReviewResult {
        let isLikelyHangup = durationMs.map { $0 <= 3_000 } ?? false
        return MessageProcessingReviewResult(
            classification: isLikelyHangup ? .likelyHangup : .unclear,
            recommendation: isLikelyHangup ? .delete : .review
        )
    }

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
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.count == 1 else {
            return candidate
        }
        for key in ["translatedText", "translated_text", "message", "text"] {
            if let result = object[key] as? String {
                let normalized = result.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty { return normalized }
            }
        }
        return candidate
    }
}

private extension Character {
    var isAsciiLetter: Bool { isASCII && isLetter }
    var isAsciiDigit: Bool { isASCII && isNumber }
    var isAsciiAlphanumeric: Bool { isAsciiLetter || isAsciiDigit }
}

#if !os(watchOS) && !os(tvOS) && canImport(Speech) && canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
extension OnDeviceMessageProcessor {
    public func process(claim: MessageProcessingClaim) async throws -> MessageProcessingCompleteRequest {
        let needs = Set(claim.needs)
        guard !needs.isEmpty, !needs.contains(where: {
            if case .unknown = $0 { return true }
            return false
        }) else {
            throw OnDeviceServiceError.badRequest("The server requested an unsupported processing step.")
        }

        var transcription: MessageProcessingTranscriptionResult?
        var translation: MessageProcessingTranslationResult?
        var moderation: MessageProcessingModerationResult?
        var review: MessageProcessingReviewResult?
        var text = claim.message.latestTranscription?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var language = claim.message.latestTranscription?.language

        if needs.contains(.transcription) {
            let sourceLanguage = claim.defaultTranscriptionLanguage ?? Self.deviceLanguageTag()
            let selection: (language: String?, locale: Locale)
            do {
                selection = try Self.sourceLanguageSelection(sourceLanguage)
            } catch {
                throw OnDeviceServiceError.unavailable(
                    "The installation's transcription language is not supported on this device."
                )
            }
            stage = .checkingAvailability
            isAvailable = await availabilityCheck(selection.locale)
            guard isAvailable else {
                throw OnDeviceServiceError.unavailable(
                    "The installation's transcription language is not supported on this device."
                )
            }
            stage = .fetchingAndTranscribing
            let result = try await audioFetcher.withFetchedAudioFile(
                url: claim.message.audio.url,
                expectedSHA256: claim.message.audio.sha256,
                maxBytes: 100 * 1024 * 1024
            ) { [transcriber] fileURL in
                try await transcriber.transcribe(audioFileURL: fileURL, language: selection.language)
            }
            let snapshot = SourceSnapshot(claim.message)
            switch result {
            case .speech(let transcript):
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw OnDeviceServiceError.badRequest("The speech service returned an invalid transcript.")
                }
                text = trimmed
                language = selection.language
                transcription = MessageProcessingTranscriptionResult(
                    expectedLatestTranscriptionId: snapshot.transcriptionId,
                    expectedLatestTranscriptionSha256: snapshot.sha256,
                    text: trimmed,
                    language: selection.language,
                    model: "apple-speech-analyzer"
                )
            case .noSpeech:
                transcription = MessageProcessingTranscriptionResult(
                    expectedLatestTranscriptionId: snapshot.transcriptionId,
                    expectedLatestTranscriptionSha256: snapshot.sha256,
                    text: "",
                    language: selection.language,
                    model: "apple-speech-analyzer"
                )
                review = OnDeviceReviewLogic.noSpeechReview(durationMs: claim.message.audio.durationMs)
            }
        }

        if needs.contains(.review) {
            review = OnDeviceReviewLogic.noSpeechReview(durationMs: claim.message.audio.durationMs)
        }
        if needs.contains(.translation) {
            guard let text, !text.isEmpty else {
                throw OnDeviceServiceError.badRequest("The claimed message has no transcript to translate.")
            }
            stage = .translating
            let result = try await translator.translate(text, sourceLanguage: language)
            guard !result.translatedText.isEmpty else {
                throw OnDeviceServiceError.badRequest("On-device translation produced no text.")
            }
            translation = MessageProcessingTranslationResult(
                transcriptionId: claim.message.latestTranscription?.id,
                expectedTranslationSha256: ReviewTextSnapshot.sha256(
                    claim.message.latestTranscription?.translationSnapshotText
                ),
                translatedText: result.translatedText,
                translatedLanguage: result.targetLanguage,
                model: result.model
            )
        }
        if needs.contains(.moderation) {
            let moderationInput = translation?.translatedText
                ?? claim.message.latestTranscription?.completedTranslation
                ?? text
            guard let moderationInput, !moderationInput.isEmpty else {
                throw OnDeviceServiceError.badRequest("The claimed message has no text to review.")
            }
            stage = .moderating
            let result = try await moderator.moderate(moderationInput)
            moderation = MessageProcessingModerationResult(
                inputSha256: ReviewTextSnapshot.sha256(moderationInput),
                flagged: result.flagged,
                recommendation: result.recommendation,
                maxScore: result.maxScore,
                model: result.model
            )
        }

        guard transcription != nil || translation != nil || moderation != nil || review != nil else {
            throw OnDeviceServiceError.badRequest("The claimed message had no processable work.")
        }
        stage = .savingModeration
        return MessageProcessingCompleteRequest(
            leaseToken: claim.leaseToken,
            transcription: transcription,
            translation: translation,
            moderation: moderation,
            review: review
        )
    }

    private static func deviceLanguageTag() -> String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
#endif
