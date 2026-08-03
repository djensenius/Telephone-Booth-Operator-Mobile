//
//  OnDeviceMessageProcessor.swift
//  TelephoneBoothOperatorMobile
//

#if !os(watchOS) && !os(tvOS) && canImport(Speech) && canImport(FoundationModels)

import Foundation
import Observation
import os

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@Observable
@MainActor
public final class OnDeviceMessageProcessor {
    public enum Stage: Equatable {
        case checkingAvailability
        case idle
        case fetchingAndTranscribing
        case translating
        case moderating
        case savingTranscript
        case savingTranslation
        case savingModeration
        case completed
        case failed(String)

        public var statusText: String? {
            switch self {
            case .checkingAvailability: return "Checking Apple Intelligence…"
            case .idle: return nil
            case .fetchingAndTranscribing: return "Downloading and transcribing audio…"
            case .translating: return "Translating the new transcript to English…"
            case .moderating: return "Generating a moderation suggestion…"
            case .savingTranscript: return "Saving transcript…"
            case .savingTranslation: return "Saving translation…"
            case .savingModeration: return "Saving suggestion…"
            case .completed: return "Transcript, translation, and suggestion saved."
            case .failed(let message): return message
            }
        }
    }

    private enum PersistenceStep: Equatable {
        case transcript
        case translation
        case moderation
    }

    private struct SourceSnapshot: Equatable {
        let transcriptionId: String?
        let status: TranscriptionStatus?
        let text: String?

        init(_ message: Message) {
            transcriptionId = message.latestTranscription?.id
            status = message.latestTranscription?.status
            text = Self.trimmed(message.latestTranscription?.text)
        }

        private static func trimmed(_ value: String?) -> String? {
            value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private struct PendingResult {
        let messageId: String
        let baseline: SourceSnapshot
        let transcript: String
        let language: String?
        let transcriptionModel: String
        let translation: TranslationResult
        let moderation: ModerationVerdict
        var step: PersistenceStep
        var transcriptionId: String?
    }

    public private(set) var stage: Stage = .checkingAvailability
    public private(set) var isAvailable = false

    public var isRunning: Bool {
        switch stage {
        case .fetchingAndTranscribing, .translating, .moderating,
             .savingTranscript, .savingTranslation, .savingModeration:
            return true
        default:
            return false
        }
    }

    public var canRetryPersistence: Bool {
        if case .failed = stage {
            return pendingResult != nil
        }
        return false
    }

    @ObservationIgnored private let audioFetcher: any AudioFetching
    @ObservationIgnored private let transcriber: any AudioTranscribing
    @ObservationIgnored private let translator: any TextTranslating
    @ObservationIgnored private let moderator: any TextModerating
    @ObservationIgnored private let logger = Logger(
        subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
        category: "OnDeviceReview"
    )
    @ObservationIgnored private var pendingResult: PendingResult?
    @ObservationIgnored private var generation = 0

    public init(
        audioFetcher: any AudioFetching = URLSessionAudioFetcher(),
        transcriber: any AudioTranscribing = AppleSpeechTranscriber(),
        translator: any TextTranslating = AppleTranslationService(),
        moderator: any TextModerating = AppleModerationService()
    ) {
        self.audioFetcher = audioFetcher
        self.transcriber = transcriber
        self.translator = translator
        self.moderator = moderator
    }

    public func refreshAvailability(locale: Locale = .current) async {
        stage = .checkingAvailability
        isAvailable = await OnDeviceCapability.supportsFullPipeline(locale: locale)
        stage = .idle
    }

    public func process(
        message: Message,
        sourceLanguage: String?,
        client: OperatorClient
    ) async {
        guard isAvailable, !isRunning else { return }
        generation += 1
        let currentGeneration = generation
        pendingResult = nil
        stage = .fetchingAndTranscribing

        do {
            let transcript = try await audioFetcher.withFetchedAudioFile(
                url: message.audio.url,
                expectedSHA256: message.audio.sha256,
                maxBytes: 100 * 1024 * 1024
            ) { [transcriber] fileURL in
                try await transcriber.transcribe(
                    audioFileURL: fileURL,
                    language: PromptSafety.normalizedLanguageTag(sourceLanguage)
                )
            }
            guard generation == currentGeneration else { return }
            let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTranscript.isEmpty else {
                fail("On-device transcription found no speech.")
                return
            }

            stage = .translating
            let translation = try await translator.translate(
                trimmedTranscript,
                sourceLanguage: sourceLanguage
            )
            guard generation == currentGeneration else { return }
            guard !translation.translatedText.isEmpty else {
                fail("On-device translation produced no text.")
                return
            }

            stage = .moderating
            let moderation = try await moderator.moderate(translation.translatedText)
            guard generation == currentGeneration else { return }

            pendingResult = PendingResult(
                messageId: message.id,
                baseline: SourceSnapshot(message),
                transcript: trimmedTranscript,
                language: translation.sourceLanguage ?? PromptSafety.normalizedLanguageTag(sourceLanguage),
                transcriptionModel: "apple-speech-analyzer",
                translation: translation,
                moderation: moderation,
                step: .transcript,
                transcriptionId: nil
            )
            await persist(client: client)
        } catch {
            guard generation == currentGeneration else { return }
            fail(Self.describe(error))
        }
    }

    public func retryPersistence(client: OperatorClient) async {
        guard pendingResult != nil, !isRunning else { return }
        await persist(client: client)
    }

    public func reset() {
        generation += 1
        pendingResult = nil
        stage = .idle
    }

    private func persist(client: OperatorClient) async {
        guard var pending = pendingResult else { return }
        do {
            if pending.step == .transcript {
                stage = .savingTranscript
                let current = try await client.fetchMessage(id: pending.messageId)
                if SourceSnapshot(current) == pending.baseline {
                    let transcription = try await client.submitTranscription(
                        messageId: pending.messageId,
                        text: pending.transcript,
                        language: pending.language,
                        model: pending.transcriptionModel
                    )
                    pending.transcriptionId = transcription.id
                } else if let transcription = current.latestTranscription,
                          transcription.status == .succeeded,
                          transcription.provider == .macApp,
                          transcription.model == pending.transcriptionModel,
                          Self.trimmed(transcription.text) == Self.trimmed(pending.transcript) {
                    pending.transcriptionId = transcription.id
                } else {
                    pendingResult = nil
                    fail("This message changed while Apple Intelligence was running. Run it again.")
                    return
                }
                pending.step = .translation
                pendingResult = pending
            }

            if pending.step == .translation {
                stage = .savingTranslation
                let current = try await client.fetchMessage(id: pending.messageId)
                guard current.latestTranscription?.id == pending.transcriptionId,
                      Self.trimmed(current.latestTranscription?.text) == Self.trimmed(pending.transcript) else {
                    pendingResult = nil
                    fail("The transcript changed before its translation could be saved.")
                    return
                }
                if current.latestTranscription?.translationStatus != .succeeded
                    || Self.trimmed(current.latestTranscription?.translatedText)
                        != Self.trimmed(pending.translation.translatedText) {
                    _ = try await client.submitTranslation(
                        messageId: pending.messageId,
                        translatedText: pending.translation.translatedText,
                        translatedLanguage: pending.translation.targetLanguage
                    )
                }
                pending.step = .moderation
                pendingResult = pending
            }

            stage = .savingModeration
            let current = try await client.fetchMessage(id: pending.messageId)
            guard current.latestTranscription?.id == pending.transcriptionId,
                  Self.trimmed(current.latestTranscription?.translatedText)
                    == Self.trimmed(pending.translation.translatedText) else {
                pendingResult = nil
                fail("The translation changed before its suggestion could be saved.")
                return
            }
            if Self.matches(pending.moderation, current.latestApplicableModeration) {
                pendingResult = nil
                stage = .completed
                return
            }
            let moderationBody = MessageModerationRequest(
                transcriptionId: pending.transcriptionId,
                flagged: pending.moderation.flagged,
                recommendation: pending.moderation.recommendation,
                maxScore: pending.moderation.maxScore,
                model: pending.moderation.model
            )
            _ = try await client.submitModeration(
                messageId: pending.messageId,
                body: moderationBody
            )
            pendingResult = nil
            stage = .completed
        } catch {
            pendingResult = pending
            fail(Self.describe(error))
        }
    }

    private func fail(_ message: String) {
        stage = .failed(message)
        logger.error("On-device processing failed without logging message content")
    }

    private static func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(
        _ expected: ModerationVerdict,
        _ existing: Moderation?
    ) -> Bool {
        guard let existing else { return false }
        return existing.flagged == expected.flagged
            && existing.recommendation == expected.recommendation
            && existing.maxScore == expected.maxScore
            && existing.model == expected.model
    }

    private static func describe(_ error: any Error) -> String {
        if let audioError = error as? AudioFetchError {
            switch audioError {
            case .invalidExpectedHash, .hashMismatch:
                return "The message audio failed its integrity check."
            case .tooLarge:
                return "The message audio is too large to process on this device."
            case .insecureURL:
                return "The message audio URL is not secure."
            case .fetchFailed:
                return "The message audio could not be downloaded."
            }
        }
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return "Apple Intelligence processing failed. Try again."
    }
}

#endif
