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
    public let reasonSummary: String?

    public init(
        flagged: Bool,
        recommendation: ModerationRecommendation,
        maxScore: Double,
        model: String,
        reasonSummary: String? = nil
    ) {
        self.flagged = flagged
        self.recommendation = recommendation
        self.maxScore = maxScore
        self.model = model
        self.reasonSummary = reasonSummary
    }
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

    /// A verdict for text the on-device model would not classify. The message is
    /// neither flagged nor scored, because nothing was actually judged — it is
    /// only routed to a person.
    public static func inconclusiveModeration(model: String) -> ModerationVerdict {
        ModerationVerdict(
            flagged: false,
            recommendation: .review,
            maxScore: 0,
            model: model,
            reasonSummary: "The on-device model would not classify this message, so it needs a human review."
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
private struct ClaimedProcessingResult {
    var transcription: MessageProcessingTranscriptionResult?
    var translation: MessageProcessingTranslationResult?
    var moderation: MessageProcessingModerationResult?
    var review: MessageProcessingReviewResult?
    var text: String?
    var language: String?

    init(message: Message) {
        text = message.latestTranscription?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        language = message.latestTranscription?.language
    }

    var hasOutput: Bool {
        transcription != nil || translation != nil || moderation != nil || review != nil
    }
}

private struct ClaimedTranscriptionResult {
    let transcription: MessageProcessingTranscriptionResult
    let review: MessageProcessingReviewResult?
    let text: String?
    let language: String?
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
extension OnDeviceMessageProcessor {
    public func process(claim: MessageProcessingClaim) async throws -> MessageProcessingCompleteRequest {
        let needs = try Self.validatedProcessingNeeds(claim.needs)
        var result = ClaimedProcessingResult(message: claim.message)

        if needs.contains(.transcription) {
            let transcription = try await processTranscription(claim)
            result.transcription = transcription.transcription
            result.review = transcription.review
            if let text = transcription.text {
                result.text = text
                result.language = transcription.language
            }
        }

        if needs.contains(.review) {
            result.review = OnDeviceReviewLogic.noSpeechReview(durationMs: claim.message.audio.durationMs)
        }
        if needs.contains(.translation) {
            result.translation = try await processTranslation(
                claim,
                text: result.text,
                language: result.language
            )
        }
        if needs.contains(.moderation) {
            result.moderation = try await processModeration(
                claim,
                translatedText: result.translation?.translatedText,
                text: result.text
            )
        }

        guard result.hasOutput else {
            throw OnDeviceServiceError.badRequest("The claimed message had no processable work.")
        }
        stage = .savingModeration
        return MessageProcessingCompleteRequest(
            leaseToken: claim.leaseToken,
            transcription: result.transcription,
            translation: result.translation,
            moderation: result.moderation,
            review: result.review
        )
    }

    private func processTranscription(
        _ claim: MessageProcessingClaim
    ) async throws -> ClaimedTranscriptionResult {
        let sourceLanguage = claim.defaultTranscriptionLanguage ?? Self.deviceLanguageTag()
        let selection = try Self.claimSourceLanguageSelection(sourceLanguage)
        stage = .checkingAvailability
        isAvailable = await availabilityCheck(selection.locale)
        guard isAvailable else {
            throw OnDeviceServiceError.unavailable(
                "The installation's transcription language is not supported on this device."
            )
        }
        stage = .fetchingAndTranscribing
        let audioResult = try await audioFetcher.withFetchedAudioFile(
            url: claim.message.audio.url,
            expectedSHA256: claim.message.audio.sha256,
            maxBytes: 100 * 1024 * 1024
        ) { [transcriber] fileURL in
            try await transcriber.transcribe(audioFileURL: fileURL, language: selection.language)
        }
        let snapshot = SourceSnapshot(claim.message)
        switch audioResult {
        case .speech(let transcript):
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw OnDeviceServiceError.badRequest("The speech service returned an invalid transcript.")
            }
            return ClaimedTranscriptionResult(
                transcription: MessageProcessingTranscriptionResult(
                    expectedLatestTranscriptionId: snapshot.transcriptionId,
                    expectedLatestTranscriptionSha256: snapshot.sha256,
                    text: text,
                    language: selection.language,
                    model: "apple-speech-analyzer"
                ),
                review: nil,
                text: text,
                language: selection.language
            )
        case .noSpeech:
            return ClaimedTranscriptionResult(
                transcription: MessageProcessingTranscriptionResult(
                    expectedLatestTranscriptionId: snapshot.transcriptionId,
                    expectedLatestTranscriptionSha256: snapshot.sha256,
                    text: "",
                    language: selection.language,
                    model: "apple-speech-analyzer"
                ),
                review: OnDeviceReviewLogic.noSpeechReview(durationMs: claim.message.audio.durationMs),
                text: nil,
                language: nil
            )
        }
    }

    private func processTranslation(
        _ claim: MessageProcessingClaim,
        text: String?,
        language: String?
    ) async throws -> MessageProcessingTranslationResult {
        guard let text, !text.isEmpty else {
            throw OnDeviceServiceError.badRequest("The claimed message has no transcript to translate.")
        }
        stage = .translating
        let translation = try await translator.translate(text, sourceLanguage: language)
        guard !translation.translatedText.isEmpty else {
            throw OnDeviceServiceError.badRequest("On-device translation produced no text.")
        }
        return MessageProcessingTranslationResult(
            transcriptionId: claim.message.latestTranscription?.id,
            expectedTranslationSha256: ReviewTextSnapshot.sha256(
                claim.message.latestTranscription?.translationSnapshotText
            ),
            translatedText: translation.translatedText,
            translatedLanguage: translation.targetLanguage,
            model: translation.model
        )
    }

    private func processModeration(
        _ claim: MessageProcessingClaim,
        translatedText: String?,
        text: String?
    ) async throws -> MessageProcessingModerationResult {
        let input = translatedText
            ?? claim.message.latestTranscription?.completedTranslation
            ?? text
        guard let input, !input.isEmpty else {
            throw OnDeviceServiceError.badRequest("The claimed message has no text to review.")
        }
        stage = .moderating
        let moderation = try await moderator.moderate(input)
        return MessageProcessingModerationResult(
            inputSha256: ReviewTextSnapshot.sha256(input),
            flagged: moderation.flagged,
            recommendation: moderation.recommendation,
            maxScore: moderation.maxScore,
            reasonSummary: moderation.reasonSummary,
            model: moderation.model
        )
    }

    private static func validatedProcessingNeeds(
        _ requestedSteps: [MessageProcessingStep]
    ) throws -> Set<MessageProcessingStep> {
        let needs = Set(requestedSteps)
        guard !needs.isEmpty, !needs.contains(where: { step in
            if case .unknown = step { return true }
            return false
        }) else {
            throw OnDeviceServiceError.badRequest("The server requested an unsupported processing step.")
        }
        return needs
    }

    private static func claimSourceLanguageSelection(
        _ sourceLanguage: String?
    ) throws -> (language: String?, locale: Locale) {
        do {
            return try sourceLanguageSelection(sourceLanguage)
        } catch {
            throw OnDeviceServiceError.unavailable(
                "The installation's transcription language is not supported on this device."
            )
        }
    }

    private static func deviceLanguageTag() -> String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
#endif
