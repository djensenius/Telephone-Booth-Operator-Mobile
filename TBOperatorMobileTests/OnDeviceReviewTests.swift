//
//  OnDeviceReviewTests.swift
//  TBOperatorMobileTests
//

import Foundation
import XCTest
@testable import TBOperatorMobile

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
        XCTAssertNil(PromptSafety.normalizedLanguageTag("ignore-all-rules"))
        XCTAssertNil(PromptSafety.normalizedLanguageTag(" "))
    }

    func testTranslationNormalization() {
        let result = OnDeviceReviewLogic.translation(
            text: "  Hello. \n",
            detectedSource: "FR",
            fallbackSource: nil,
            model: "test-model"
        )
        XCTAssertEqual(result.translatedText, "Hello.")
        XCTAssertEqual(result.sourceLanguage, "fr")
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

    func testSubmissionBodiesNormalizeValues() {
        let transcript = MessageTranscriptionRequest(
            text: " hello ",
            language: " fr ",
            model: " apple-speech-analyzer "
        )
        XCTAssertEqual(transcript.text, "hello")
        XCTAssertEqual(transcript.language, "fr")
        XCTAssertEqual(transcript.model, "apple-speech-analyzer")

        let moderation = MessageModerationRequest(
            transcriptionId: " t1 ",
            flagged: true,
            recommendation: .reject,
            maxScore: 2,
            model: " apple-foundation-models "
        )
        XCTAssertEqual(moderation.transcriptionId, "t1")
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

    func testModerationPredatingTranslationIsNotApplicable() {
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
        let staleModeration = Moderation(
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
            latestModeration: staleModeration
        )

        XCTAssertNil(message.latestApplicableModeration)

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
