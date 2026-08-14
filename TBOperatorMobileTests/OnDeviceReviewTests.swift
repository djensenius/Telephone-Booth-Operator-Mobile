// swiftlint:disable file_length
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

private struct WrappedCancellationAudioFetcher: AudioFetching {
    func withFetchedAudioFile<T: Sendable>(
        url: URL,
        expectedSHA256: String,
        maxBytes: Int,
        _ body: @Sendable (URL) async throws -> T
    ) async throws -> T {
        do {
            try await Task.sleep(for: .seconds(30))
        } catch is CancellationError {
            throw AudioFetchError.fetchFailed
        }
        return try await body(FileManager.default.temporaryDirectory.appendingPathComponent("audio.flac"))
    }
}

private struct StubTranscriber: AudioTranscribing {
    let operation: @Sendable () async throws -> AudioTranscriptionResult
    func transcribe(
        audioFileURL: URL,
        language: String?
    ) async throws -> AudioTranscriptionResult {
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

private actor StubClaimedProcessingClient: MessageProcessingPersisting {
    private var claims: [MessageProcessingClaim]
    private let completionConflict: String?
    private(set) var completedRequests: [MessageProcessingCompleteRequest] = []
    private var releasedCount = 0
    private var failedCount = 0

    init(claims: [MessageProcessingClaim], completionConflict: String? = nil) {
        self.claims = claims
        self.completionConflict = completionConflict
    }

    func fetchMessageProcessingSummary() async throws -> MessageProcessingSummary {
        MessageProcessingSummary(
            queued: claims.count,
            leased: completedRequests.count,
            terminal: 0,
            needs: .init(transcription: 0, translation: 0, moderation: 0, review: claims.count),
            generatedAt: Date()
        )
    }

    func claimMessageProcessing(
        _ request: MessageProcessingClaimRequest
    ) async throws -> MessageProcessingClaim? {
        guard !claims.isEmpty else { return nil }
        return claims.removeFirst()
    }

    func heartbeatMessageProcessing(
        messageId: String,
        request: MessageProcessingHeartbeatRequest
    ) async throws -> MessageProcessingHeartbeatResponse {
        MessageProcessingHeartbeatResponse(
            succeeded: true,
            leaseExpiresAt: Date().addingTimeInterval(300)
        )
    }

    func releaseMessageProcessing(messageId: String, leaseToken: String) async throws {
        releasedCount += 1
    }

    func failMessageProcessing(
        messageId: String,
        request: MessageProcessingFailRequest
    ) async throws -> MessageProcessingFailResponse {
        failedCount += 1
        MessageProcessingFailResponse(succeeded: true, terminal: false)
    }

    func completeMessageProcessing(
        messageId: String,
        request: MessageProcessingCompleteRequest
    ) async throws -> MessageProcessingCompleteResponse {
        if let completionConflict {
            throw OperatorError.httpError(
                status: 409,
                body: #"{"error":"\#(completionConflict)"}"#
            )
        }
        completedRequests.append(request)
        return MessageProcessingCompleteResponse(
            message: DemoData.message(id: messageId),
            needs: []
        )
    }

    func completedCount() -> Int {
        completedRequests.count
    }

    func releaseCount() -> Int {
        releasedCount
    }

    func failureCount() -> Int {
        failedCount
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
            text: "```json\n{\"message\":\"Hello.\"}\n```",
            detectedSource: "und",
            fallbackSource: "fr-CA",
            model: "test-model"
        )
        XCTAssertEqual(result.translatedText, "Hello.")
        XCTAssertEqual(result.sourceLanguage, "fr-ca")
        XCTAssertEqual(result.targetLanguage, "en")
        XCTAssertEqual(result.model, "test-model")
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
    func testInconclusiveModerationIsUnflaggedReview() {
        let verdict = OnDeviceReviewLogic.inconclusiveModeration(model: "test-model")
        XCTAssertFalse(verdict.flagged)
        XCTAssertEqual(verdict.recommendation, .review)
        XCTAssertEqual(verdict.maxScore, 0)
        XCTAssertEqual(verdict.model, "test-model")
        XCTAssertNotNil(verdict.reasonSummary)
    }
    func testNoSpeechAtThreeSecondsIsLikelyHangup() {
        let result = OnDeviceReviewLogic.noSpeechReview(durationMs: 3_000)
        XCTAssertEqual(result.classification, .likelyHangup)
        XCTAssertEqual(result.recommendation, .delete)
    }
    func testNoSpeechOverThreeSecondsOrUnknownNeedsReview() {
        XCTAssertEqual(
            OnDeviceReviewLogic.noSpeechReview(durationMs: 3_001).classification,
            .unclear
        )
        XCTAssertEqual(
            OnDeviceReviewLogic.noSpeechReview(durationMs: nil).recommendation,
            .review
        )
    }
    func testClaimRequestEncodesCapabilitiesAndLease() throws {
        let data = try OperatorJSON.encoder.encode(
            MessageProcessingClaimRequest(capabilities: [.translation, .moderation], leaseSeconds: 999)
        )
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(body?["leaseSeconds"] as? Int, 900)
        XCTAssertEqual(body?["capabilities"] as? [String], ["translation", "moderation"])
    }
    func testProcessingResultsEncodeNullStaleSnapshots() throws {
        let result = MessageProcessingTranscriptionResult(
            expectedLatestTranscriptionId: nil,
            expectedLatestTranscriptionSha256: nil,
            text: "hello",
            language: "en",
            model: "apple-speech-analyzer"
        )
        let body = try JSONSerialization.jsonObject(
            with: OperatorJSON.encoder.encode(result)
        ) as? [String: Any]
        XCTAssertTrue(body?["expectedLatestTranscriptionId"] is NSNull)
        XCTAssertTrue(body?["expectedLatestTranscriptionSha256"] is NSNull)
    }
    func testClaimDecodesInstallationLanguage() throws {
        let data = Data(#"""
        {
          "claim": {
            "message": {
              "id": "message-1",
              "status": "pending",
              "createdAt": "2026-08-14T12:00:00Z",
              "audio": {
                "url": "https://example.com/audio.flac",
                "sha256": "abc",
                "durationMs": 3000
              }
            },
            "needs": ["transcription"],
            "leaseToken": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "leaseExpiresAt": "2026-08-14T12:05:00Z",
            "defaultTranscriptionLanguage": "fr-CA"
          }
        }
        """#.utf8)
        let response = try OperatorJSON.decoder.decode(MessageProcessingClaimResponse.self, from: data)
        XCTAssertEqual(response.claim?.needs, [.transcription])
        XCTAssertEqual(response.claim?.defaultTranscriptionLanguage, "fr-CA")
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
}

extension OnDeviceReviewTests {
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
            return .speech("bonjour")
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
    func testClaimedProcessorPersistsNoSpeechAsReview() async throws {
        let message = DemoData.message(id: "demo-message-3")
        let claim = MessageProcessingClaim(
            message: message,
            needs: [.transcription],
            leaseToken: String(repeating: "a", count: 32),
            leaseExpiresAt: Date().addingTimeInterval(300),
            defaultTranscriptionLanguage: "fr-CA"
        )
        let processor = makeProcessor(transcriber: StubTranscriber { .noSpeech })
        let result = try await processor.process(claim: claim)
        XCTAssertEqual(result.transcription?.text, "")
        XCTAssertEqual(result.review?.classification, .unclear)
        XCTAssertEqual(result.review?.recommendation, .review)
        XCTAssertNil(result.translation)
        XCTAssertNil(result.moderation)
    }
    @MainActor
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func testCoordinatorProcessesClaimsSerially() async throws {
        let message = DemoData.message(id: "demo-message-3")
        let first = MessageProcessingClaim(
            message: message,
            needs: [.review],
            leaseToken: String(repeating: "a", count: 32),
            leaseExpiresAt: Date().addingTimeInterval(300),
            defaultTranscriptionLanguage: nil
        )
        let second = MessageProcessingClaim(
            message: message,
            needs: [.review],
            leaseToken: String(repeating: "b", count: 32),
            leaseExpiresAt: Date().addingTimeInterval(300),
            defaultTranscriptionLanguage: nil
        )
        let client = StubClaimedProcessingClient(claims: [first, second])
        let coordinator = AutomaticMessageProcessingCoordinator(
            client: client,
            processor: makeProcessor(),
            socket: nil,
            capabilityCheck: { _ in true }
        )
        coordinator.setActive(true)
        try await Task.sleep(for: .milliseconds(150))
        coordinator.setActive(false)
        XCTAssertEqual(await client.completedCount(), 2)
    }
    @MainActor
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func testCoordinatorTreatsLeaseLossAsRefresh() async throws {
        let claim = MessageProcessingClaim(
            message: DemoData.message(id: "demo-message-3"),
            needs: [.review],
            leaseToken: String(repeating: "a", count: 32),
            leaseExpiresAt: Date().addingTimeInterval(300),
            defaultTranscriptionLanguage: nil
        )
        let client = StubClaimedProcessingClient(
            claims: [claim],
            completionConflict: "lease_lost"
        )
        let coordinator = AutomaticMessageProcessingCoordinator(
            client: client,
            processor: makeProcessor(),
            socket: nil,
            capabilityCheck: { _ in true }
        )
        coordinator.setActive(true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(coordinator.canRetry)
        coordinator.setActive(false)
    }

    @MainActor
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func testCoordinatorReleasesSnapshotConflictBeforeReclaiming() async throws {
        let claim = MessageProcessingClaim(
            message: DemoData.message(id: "demo-message-3"),
            needs: [.review],
            leaseToken: String(repeating: "a", count: 32),
            leaseExpiresAt: Date().addingTimeInterval(300),
            defaultTranscriptionLanguage: nil
        )
        let client = StubClaimedProcessingClient(
            claims: [claim],
            completionConflict: "claim_snapshot_stale"
        )
        let coordinator = AutomaticMessageProcessingCoordinator(
            client: client,
            processor: makeProcessor(),
            socket: nil,
            capabilityCheck: { _ in true }
        )

        coordinator.setActive(true)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(coordinator.canRetry)
        XCTAssertEqual(await client.releaseCount(), 1)
        XCTAssertEqual(await client.failureCount(), 0)
        coordinator.setActive(false)
    }

    @MainActor
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func testCoordinatorReleasesUnsupportedInstallationLanguageWithoutFailing() async throws {
        let claim = MessageProcessingClaim(
            message: DemoData.message(id: "demo-message-3"),
            needs: [.transcription],
            leaseToken: String(repeating: "a", count: 32),
            leaseExpiresAt: Date().addingTimeInterval(300),
            defaultTranscriptionLanguage: "fr-CA"
        )
        let client = StubClaimedProcessingClient(claims: [claim])
        let coordinator = AutomaticMessageProcessingCoordinator(
            client: client,
            processor: makeProcessor(availabilityCheck: { _ in false }),
            socket: nil,
            capabilityCheck: { _ in true }
        )

        coordinator.setActive(true)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(coordinator.status, .paused)
        XCTAssertEqual(await client.releaseCount(), 1)
        XCTAssertEqual(await client.failureCount(), 0)
    }

    @MainActor
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func testCoordinatorKeepsPausedStatusWhenFetchCancellationIsWrapped() async throws {
        let claim = MessageProcessingClaim(
            message: DemoData.message(id: "demo-message-3"),
            needs: [.transcription],
            leaseToken: String(repeating: "a", count: 32),
            leaseExpiresAt: Date().addingTimeInterval(300),
            defaultTranscriptionLanguage: "fr-CA"
        )
        let client = StubClaimedProcessingClient(claims: [claim])
        let coordinator = AutomaticMessageProcessingCoordinator(
            client: client,
            processor: makeProcessor(audioFetcher: WrappedCancellationAudioFetcher()),
            socket: nil,
            capabilityCheck: { _ in true }
        )

        coordinator.setActive(true)
        for _ in 0..<10 where coordinator.currentMessageID == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(coordinator.currentMessageID)
        coordinator.setActive(false)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(coordinator.status, .paused)
        XCTAssertEqual(await client.releaseCount(), 1)
        XCTAssertEqual(await client.failureCount(), 0)
    }

    @MainActor
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    private func makeProcessor(
        audioFetcher: any AudioFetching = StubAudioFetcher(),
        transcriber: any AudioTranscribing = StubTranscriber { .speech("bonjour") },
        availabilityCheck: @escaping @Sendable (Locale) async -> Bool = { _ in true }
    ) -> OnDeviceMessageProcessor {
        OnDeviceMessageProcessor(
            audioFetcher: audioFetcher,
            transcriber: transcriber,
            translator: StubTranslator(),
            moderator: StubModerator(),
            availabilityCheck: availabilityCheck
        )
    }
}
