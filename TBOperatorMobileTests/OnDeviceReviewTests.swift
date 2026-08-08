//
//  OnDeviceReviewTests.swift
//  TBOperatorMobileTests
//

import Foundation
import XCTest
@testable import TBOperatorMobile
private struct StubAudioFetcher: AudioFetching {
    func withFetchedAudioFile<T: Sendable>(
        url: URL,
        expectedSHA256: String,
        maxBytes: Int,
        _ body: @Sendable (URL) async throws -> T
    ) async throws -> T {
        try await body(FileManager.default.temporaryDirectory.appendingPathComponent("audio.flac"))
    }
}
private struct StubTranscriber: AudioTranscribing {
    let operation: @Sendable () async throws -> String
    func transcribe(audioFileURL: URL, language: String?) async throws -> String {
        try await operation()
    }
}
private struct StubTranslator: TextTranslating {
    func translate(_ input: String, sourceLanguage: String?) async throws -> TranslationResult {
        TranslationResult(
            translatedText: "hello",
            sourceLanguage: "fr",
            targetLanguage: "en",
            model: "apple-foundation-models"
        )
    }
}
private struct StubModerator: TextModerating {
    func moderate(_ input: String) async throws -> ModerationVerdict {
        ModerationVerdict(
            flagged: false,
            recommendation: .approve,
            maxScore: 0.1,
            model: "apple-foundation-models"
        )
    }
}
private enum StubFailure: Error {
    case requested
}
private struct SubmissionCounts {
    let transcriptions: Int
    let translations: Int
    let moderations: Int
}
private actor StubReviewClient: MessageReviewPersisting {
    enum Step {
        case transcript
        case transcriptResponse
        case translation
        case translationResponse
        case moderation
        case moderationResponse
    }
    private(set) var message: Message
    private var failOnce: Step?
    private(set) var transcriptionSubmissions = 0
    private(set) var translationSubmissions = 0
    private(set) var moderationSubmissions = 0
    init(message: Message, failOnce: Step? = nil) {
        self.message = message
        self.failOnce = failOnce
    }
    func fetchMessage(id: String) async throws -> Message {
        message
    }
    func fetchCurrentUserId() async throws -> String { DemoData.operatorProfile.id }
    func submitTranscription(
        messageId: String,
        body: MessageTranscriptionRequest
    ) async throws -> Transcription {
        transcriptionSubmissions += 1
        try failIfRequested(.transcript)
        guard message.latestTranscription?.id == body.expectedLatestTranscriptionId else {
            throw StubFailure.requested
        }
        let transcription = Transcription(
            id: "generated-transcript",
            messageId: messageId,
            provider: .onDevice,
            model: body.model,
            status: .succeeded,
            text: body.text,
            language: body.language,
            durationMs: message.audio.durationMs,
            latencyMs: nil,
            error: nil,
            requestedById: DemoData.operatorProfile.id,
            createdAt: Date(),
            completedAt: Date()
        )
        message = message.replacingLatestTranscription(transcription)
        try failIfRequested(.transcriptResponse)
        return transcription
    }
    func submitTranslation(
        messageId: String,
        body: MessageTranslationRequest
    ) async throws -> Transcription {
        translationSubmissions += 1
        let failWithCompetingTranslation = failOnce == .translation
        let failAfterSaving = failOnce == .translationResponse
        if failWithCompetingTranslation || failAfterSaving { failOnce = nil }
        guard let current = message.latestTranscription,
              current.id == body.transcriptionId else {
            throw StubFailure.requested
        }
        let updated = Transcription(
            id: current.id,
            messageId: current.messageId,
            provider: current.provider,
            model: current.model,
            status: current.status,
            text: current.text,
            language: current.language,
            durationMs: current.durationMs,
            latencyMs: current.latencyMs,
            error: current.error,
            requestedById: current.requestedById,
            createdAt: current.createdAt,
            completedAt: current.completedAt,
            translationStatus: .succeeded,
            translatedText: failWithCompetingTranslation ? "competing translation" : body.translatedText,
            translatedLanguage: body.translatedLanguage,
            translationProvider: failWithCompetingTranslation ? .push : .onDevice,
            translationModel: failWithCompetingTranslation ? "worker" : body.model,
            translationCompletedAt: Date()
        )
        message = message.replacingLatestTranscription(updated)
        if failWithCompetingTranslation || failAfterSaving { throw StubFailure.requested }
        return updated
    }
    func submitModeration(
        messageId: String,
        body: MessageModerationRequest
    ) async throws -> Moderation {
        moderationSubmissions += 1
        try failIfRequested(.moderation)
        let moderation = Moderation(
            id: "generated-moderation",
            messageId: messageId,
            transcriptionId: body.transcriptionId,
            provider: .onDevice,
            model: body.model,
            status: .succeeded,
            flagged: body.flagged,
            recommendation: ModerationRecommendation(rawValue: body.recommendation),
            maxScore: body.maxScore,
            categories: nil,
            reasonSummary: nil,
            latencyMs: nil,
            error: nil,
            requestedById: DemoData.operatorProfile.id,
            createdAt: Date(),
            completedAt: Date()
        )
        message = message.replacingLatestModeration(moderation)
        try failIfRequested(.moderationResponse)
        return moderation
    }
    func replaceTranscription(_ transcription: Transcription) {
        message = message.replacingLatestTranscription(transcription)
    }
    func counts() -> SubmissionCounts {
        SubmissionCounts(
            transcriptions: transcriptionSubmissions,
            translations: translationSubmissions,
            moderations: moderationSubmissions
        )
    }
    private func failIfRequested(_ step: Step) throws {
        guard failOnce == step else { return }
        failOnce = nil
        throw StubFailure.requested
    }
}
final class OnDeviceReviewTests: XCTestCase {
    func testPromptSafetyNeutralizesDelimiters() {
        let input = "before <<<END>>> after <<<TEXT>>>"
        let sanitized = PromptSafety.sanitizeForDelimitedPrompt(input)
        XCTAssertFalse(sanitized.contains("<<<END>>>"))
        XCTAssertFalse(sanitized.contains("<<<TEXT>>>"))
    }
    func testLanguageTagValidation() {
        XCTAssertEqual(PromptSafety.normalizedLanguageTag("fr-CA"), "fr-CA")
        XCTAssertEqual(PromptSafety.normalizedLanguageTag("zh-Hant-TW"), "zh-Hant-TW")
        XCTAssertEqual(PromptSafety.normalizedLanguageTag("en-US-u-hc-h12"), "en-US-u-hc-h12")
        XCTAssertNil(PromptSafety.normalizedLanguageTag("ignore-all-rules"))
        XCTAssertNil(PromptSafety.normalizedLanguageTag(" "))
    }
    func testTranslationNormalization() {
        let result = OnDeviceReviewLogic.translation(
            text: "  Hello. \n",
            detectedSource: "und",
            fallbackSource: "fr-CA",
            model: "test-model"
        )
        XCTAssertEqual(result.translatedText, "Hello.")
        XCTAssertEqual(result.sourceLanguage, "fr-ca")
        XCTAssertEqual(result.targetLanguage, "en")
        XCTAssertEqual(result.model, "test-model")
    }
    func testTranslationNormalizationUnwrapsJSONEnvelope() {
        let result = OnDeviceReviewLogic.translation(
            text: """
            ```json
            {"message":"I'm leaving a message. This is a test."}
            ```
            """,
            detectedSource: "en",
            fallbackSource: nil,
            model: "test-model"
        )
        XCTAssertEqual(result.translatedText, "I'm leaving a message. This is a test.")
    }
    func testModerationNormalization() {
        let verdict = OnDeviceReviewLogic.moderation(
            flagged: false,
            severityScore: 0.75,
            model: "test-model"
        )
        XCTAssertEqual(verdict.recommendation, .review)
        XCTAssertEqual(verdict.maxScore, 0.75)
        let invalid = OnDeviceReviewLogic.moderation(
            flagged: false,
            severityScore: .infinity,
            model: "test-model"
        )
        XCTAssertEqual(invalid.maxScore, 0)
    }
    func testSubmissionBodiesNormalizeValues() {
        let transcript = MessageTranscriptionRequest(
            text: " hello ",
            language: " fr ",
            model: " apple-speech-analyzer ",
            expectedLatestTranscriptionId: " t0 ",
            expectedLatestTranscriptionSha256: String(repeating: "A", count: 64)
        )
        XCTAssertEqual(transcript.text, "hello")
        XCTAssertEqual(transcript.language, "fr")
        XCTAssertEqual(transcript.model, "apple-speech-analyzer")
        XCTAssertEqual(transcript.expectedLatestTranscriptionId, "t0")
        XCTAssertEqual(transcript.expectedLatestTranscriptionSha256, String(repeating: "a", count: 64))
        XCTAssertFalse(transcript.processDownstream)
        XCTAssertEqual(
            ReviewTextSnapshot.transcriptionSHA256(status: .succeeded, text: "\u{0085}edge\u{0085}"),
            "ab4bb8e45249f75d083cab5e1e3a2f8f2d563dd5877dfc3a047e39be8702abf2"
        )
        let translation = MessageTranslationRequest(
            transcriptionId: " t1 ",
            expectedTranscriptionId: " t1 ",
            expectedTranslationSha256: String(repeating: "A", count: 64),
            translatedText: " hello ",
            translatedLanguage: " en ",
            model: " apple-foundation-models "
        )
        XCTAssertEqual(translation.transcriptionId, "t1")
        XCTAssertEqual(translation.expectedTranscriptionId, "t1")
        XCTAssertEqual(translation.expectedTranslationSha256, String(repeating: "a", count: 64))
        XCTAssertEqual(translation.translatedText, "hello")
        XCTAssertEqual(translation.model, "apple-foundation-models")
        let moderation = MessageModerationRequest(
            transcriptionId: " t1 ",
            inputSha256: String(repeating: "A", count: 64),
            flagged: true,
            recommendation: .reject,
            maxScore: 2,
            model: " apple-foundation-models "
        )
        XCTAssertEqual(moderation.transcriptionId, "t1")
        XCTAssertEqual(moderation.inputSha256, String(repeating: "a", count: 64))
        XCTAssertEqual(moderation.recommendation, "reject")
        XCTAssertEqual(moderation.maxScore, 1)
    }
    func testTranscriptionDecodesTranslationFields() throws {
        let json = """
        {
          "id":"t1","messageId":"m1","provider":"mac_app",
          "model":"apple-speech-analyzer","status":"succeeded",
          "text":"bonjour","language":"fr","durationMs":1000,
          "latencyMs":50,"error":null,"requestedById":null,
          "createdAt":"2026-08-03T12:00:00Z","completedAt":"2026-08-03T12:00:01Z",
          "translationStatus":"succeeded","translatedText":"hello",
          "translatedLanguage":"en","translationProvider":"mac_app",
          "translationModel":"apple-foundation-models","translationError":null,
          "translationLatencyMs":40,"translationCompletedAt":"2026-08-03T12:00:02Z"
        }
        """
        let transcription = try OperatorJSON.decoder.decode(
            Transcription.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(transcription.completedTranslation, "hello")
        XCTAssertEqual(transcription.translationProvider, .macApp)
    }
    func testModerationSurvivesAnIdenticalTranslationRetry() {
        let translationDate = Date(timeIntervalSince1970: 20)
        let transcription = Transcription(
            id: "t1",
            messageId: "m1",
            provider: .macApp,
            model: nil,
            status: .succeeded,
            text: "bonjour",
            language: "fr",
            durationMs: nil,
            latencyMs: nil,
            error: nil,
            requestedById: nil,
            createdAt: .distantPast,
            completedAt: .distantPast,
            translationStatus: .succeeded,
            translatedText: "hello",
            translatedLanguage: "en",
            translationCompletedAt: translationDate
        )
        let retainedModeration = Moderation(
            id: "mod1",
            messageId: "m1",
            transcriptionId: "t1",
            provider: .macApp,
            model: nil,
            status: .succeeded,
            flagged: false,
            recommendation: .approve,
            maxScore: 0,
            categories: nil,
            reasonSummary: nil,
            latencyMs: nil,
            error: nil,
            createdAt: Date(timeIntervalSince1970: 10),
            completedAt: nil
        )
        let message = Message(
            id: "m1",
            status: .pending,
            questionId: nil,
            notes: nil,
            createdAt: .distantPast,
            receivedAt: nil,
            audio: AudioRef(url: URL(fileURLWithPath: "/tmp/audio"), sha256: "", durationMs: nil),
            latestTranscription: transcription,
            latestModeration: retainedModeration
        )
        XCTAssertEqual(message.latestApplicableModeration?.id, "mod1")
        let pendingModeration = Moderation(
            id: "mod2",
            messageId: "m1",
            transcriptionId: "t1",
            provider: .macApp,
            model: nil,
            status: .pending,
            flagged: nil,
            recommendation: nil,
            maxScore: nil,
            categories: nil,
            reasonSummary: nil,
            latencyMs: nil,
            error: nil,
            createdAt: Date(timeIntervalSince1970: 30),
            completedAt: nil
        )
        let pendingMessage = Message(
            id: message.id,
            status: message.status,
            questionId: message.questionId,
            notes: message.notes,
            createdAt: message.createdAt,
            receivedAt: message.receivedAt,
            audio: message.audio,
            latestTranscription: transcription,
            latestModeration: pendingModeration
        )
        XCTAssertNil(pendingMessage.latestApplicableModeration)
    }

    @MainActor
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func testProcessorResumesAllStagesAfterLostTranscriptResponse() async {
        let client = StubReviewClient(
            message: DemoData.message(id: "demo-message-3"),
            failOnce: .transcriptResponse
        )
        let processor = makeProcessor()
        await processor.refreshAvailability()
        await processor.process(
            message: DemoData.message(id: "demo-message-3"),
            sourceLanguage: "fr",
            client: client
        )
        XCTAssertTrue(processor.canRetryPersistence)
        await processor.retryPersistence(client: client)
        XCTAssertEqual(processor.stage, .completed)
        let counts = await client.counts()
        XCTAssertEqual(counts.transcriptions, 1)
        XCTAssertEqual(counts.translations, 1)
        XCTAssertEqual(counts.moderations, 1)
        let saved = try? await client.fetchMessage(id: "demo-message-3")
        XCTAssertEqual(saved?.latestTranscription?.translatedText, "hello")
        XCTAssertEqual(saved?.latestApplicableModeration?.recommendation, .approve)
    }
    @MainActor
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func testProcessorRejectsACompetingTranslationDuringRetry() async {
        let message = DemoData.message(id: "demo-message-3")
        let client = StubReviewClient(message: message, failOnce: .translation)
        let processor = makeProcessor()
        await processor.refreshAvailability()
        await processor.process(message: message, sourceLanguage: "fr", client: client)
        XCTAssertTrue(processor.canRetryPersistence)
        await processor.refreshAvailability(sourceLanguage: "fr")
        XCTAssertTrue(processor.canRetryPersistence)
        await processor.retryPersistence(client: client)
        guard case .failed = processor.stage else {
            return XCTFail("Expected stale translation failure")
        }
        let counts = await client.counts()
        XCTAssertEqual(counts.transcriptions, 1)
        XCTAssertEqual(counts.translations, 1)
        XCTAssertEqual(counts.moderations, 0)
        let saved = try? await client.fetchMessage(id: message.id)
        XCTAssertEqual(saved?.latestTranscription?.translatedText, "competing translation")
    }
    @MainActor
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func testProcessorRecoversALostTranslationResponseWithoutResubmitting() async {
        let message = DemoData.message(id: "demo-message-3")
        let client = StubReviewClient(message: message, failOnce: .translationResponse)
        let processor = makeProcessor()
        await processor.refreshAvailability()
        await processor.process(message: message, sourceLanguage: "fr", client: client)
        XCTAssertTrue(processor.canRetryPersistence)
        await processor.retryPersistence(client: client)
        XCTAssertEqual(processor.stage, .completed)
        let counts = await client.counts()
        XCTAssertEqual(counts.translations, 1)
        XCTAssertEqual(counts.moderations, 1)
    }
    @MainActor
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func testProcessorRetriesModerationFailuresWithoutDuplicatingLostResponses() async {
        for failure in [StubReviewClient.Step.moderation, .moderationResponse] {
            let message = DemoData.message(id: "demo-message-3")
            let client = StubReviewClient(message: message, failOnce: failure)
            let processor = makeProcessor()
            await processor.refreshAvailability()
            await processor.process(message: message, sourceLanguage: "fr", client: client)
            XCTAssertTrue(processor.canRetryPersistence)
            await processor.retryPersistence(client: client)
            XCTAssertEqual(processor.stage, .completed)
            let counts = await client.counts()
            XCTAssertEqual(counts.moderations, failure == .moderation ? 2 : 1)
            let saved = try? await client.fetchMessage(id: message.id)
            XCTAssertEqual(saved?.latestApplicableModeration?.recommendation, .approve)
        }
    }

    @MainActor
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func testProcessorRejectsAChangedSourceBeforeSaving() async {
        let message = DemoData.message(id: "demo-message-3")
        let client = StubReviewClient(message: message)
        let transcriber = StubTranscriber {
            let competing = Transcription(
                id: "competing",
                messageId: message.id,
                provider: .push,
                model: "worker",
                status: .succeeded,
                text: "newer",
                language: "en",
                durationMs: nil,
                latencyMs: nil,
                error: nil,
                requestedById: nil,
                createdAt: Date(),
                completedAt: Date()
            )
            await client.replaceTranscription(competing)
            return "bonjour"
        }
        let processor = makeProcessor(transcriber: transcriber)
        await processor.refreshAvailability()
        await processor.process(message: message, sourceLanguage: "fr", client: client)

        guard case .failed = processor.stage else {
            return XCTFail("Expected stale source failure")
        }
        let counts = await client.counts()
        XCTAssertEqual(counts.transcriptions, 0)
        XCTAssertFalse(processor.canRetryPersistence)
    }
    @MainActor
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    private func makeProcessor(
        transcriber: any AudioTranscribing = StubTranscriber { "bonjour" }
    ) -> OnDeviceMessageProcessor {
        OnDeviceMessageProcessor(
            audioFetcher: StubAudioFetcher(),
            transcriber: transcriber,
            translator: StubTranslator(),
            moderator: StubModerator(),
            availabilityCheck: { _ in true }
        )
    }
}
