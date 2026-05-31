//
//  UnknownEnumTests.swift
//

import XCTest
@testable import TBOperatorMobile

final class UnknownEnumTests: XCTestCase {

    // MARK: - BoothState

    func testBoothStateDecodesUnknownValue() throws {
        let json = """
        {
          "state": "maintenance",
          "updatedAt": "2026-05-23T14:32:11Z",
          "currentQuestionId": null,
          "currentMessageId": null,
          "lastError": null
        }
        """
        let status = try OperatorJSON.decoder.decode(BoothStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.state, .unknown("maintenance"))
        XCTAssertEqual(status.state.rawValue, "maintenance")
        XCTAssertFalse(status.state.isCallActive)
    }

    func testBoothStateRoundTripsUnknownValue() throws {
        let state = BoothState(rawValue: "future_state")
        XCTAssertEqual(state, .unknown("future_state"))
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BoothState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    // MARK: - BoothEventType

    func testBoothEventTypeDecodesUnknownValue() throws {
        let json = """
        {
          "items": [
            {
              "id": "aaa",
              "eventId": "evt-x",
              "boothId": "booth-a",
              "bootId": "boot-z",
              "type": "firmware_update",
              "occurredAt": "2026-05-23T14:32:00.000Z",
              "receivedAt": "2026-05-23T14:32:00.500Z",
              "sessionId": null,
              "recordingId": null
            }
          ],
          "nextCursor": null
        }
        """
        let page = try OperatorJSON.decoder.decode(EventList.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.first?.type, .unknown("firmware_update"))
        XCTAssertEqual(page.items.first?.type.displayName, "Firmware Update")
    }

    // MARK: - MessageStatus

    func testMessageStatusDecodesUnknownValue() throws {
        let status = try JSONDecoder().decode(MessageStatus.self, from: Data("\"archived\"".utf8))
        XCTAssertEqual(status, .unknown("archived"))
        XCTAssertEqual(status.displayName, "Archived")
    }

    // MARK: - AiProvider

    func testAiProviderDecodesUnknownValue() throws {
        let provider = try JSONDecoder().decode(AiProvider.self, from: Data("\"anthropic\"".utf8))
        XCTAssertEqual(provider, .unknown("anthropic"))
        XCTAssertEqual(provider.displayName, "anthropic")
    }

    // MARK: - TranscriptionStatus

    func testTranscriptionStatusDecodesUnknownValue() throws {
        let status = try JSONDecoder().decode(
            TranscriptionStatus.self, from: Data("\"processing\"".utf8)
        )
        XCTAssertEqual(status, .unknown("processing"))
        XCTAssertEqual(status.displayName, "Processing")
    }

    // MARK: - ModerationRecommendation

    func testModerationRecommendationDecodesUnknownValue() throws {
        let rec = try JSONDecoder().decode(
            ModerationRecommendation.self, from: Data("\"escalate\"".utf8)
        )
        XCTAssertEqual(rec, .unknown("escalate"))
        XCTAssertEqual(rec.displayName, "Escalate")
    }

    // MARK: - CallOutcome

    func testCallOutcomeDecodesUnknownValue() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000099",
          "boothId": "booth-a",
          "bootId": "11111111-1111-1111-1111-111111111111",
          "startedAt": "2026-05-23T14:30:00Z",
          "endedAt": "2026-05-23T14:32:11Z",
          "digitsDialed": null,
          "outcome": "timeout_no_input",
          "recordingId": null,
          "durationMs": 60000
        }
        """
        let session = try OperatorJSON.decoder.decode(CallSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.outcome, .unknown("timeout_no_input"))
        XCTAssertEqual(session.outcome?.displayName, "Timeout No Input")
        XCTAssertFalse(session.outcome?.isSuccess == true)
    }

    // MARK: - MobileDevicePlatform

    func testMobileDevicePlatformDecodesUnknownValue() throws {
        let platform = try JSONDecoder().decode(
            MobileDevicePlatform.self, from: Data("\"android\"".utf8)
        )
        XCTAssertEqual(platform, .unknown("android"))
        XCTAssertEqual(platform.rawValue, "android")
    }

    // MARK: - RuntimeMode

    func testRuntimeModeDecodesKnownValues() throws {
        let real = try JSONDecoder().decode(RuntimeMode.self, from: Data("\"real\"".utf8))
        XCTAssertEqual(real, .real)
        XCTAssertTrue(real.isReal)
        XCTAssertFalse(real.shouldDisplayBadge)

        let mock = try JSONDecoder().decode(RuntimeMode.self, from: Data("\"mock\"".utf8))
        XCTAssertEqual(mock, .mock)
        XCTAssertEqual(mock.shortLabel, "MOCK")

        let sim = try JSONDecoder().decode(RuntimeMode.self, from: Data("\"simulator\"".utf8))
        XCTAssertEqual(sim, .simulator)
        XCTAssertEqual(sim.shortLabel, "SIM")
    }

    func testRuntimeModeDecodesUnknownValue() throws {
        let mode = try JSONDecoder().decode(RuntimeMode.self, from: Data("\"hardware-rev3\"".utf8))
        XCTAssertEqual(mode, .unknown("hardware-rev3"))
        XCTAssertEqual(mode.rawValue, "hardware-rev3")
        XCTAssertFalse(mode.isReal)
    }

    func testRuntimeModeRoundTrips() throws {
        for mode: RuntimeMode in [.real, .mock, .simulator, .unknown("custom")] {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(RuntimeMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    // MARK: - QuestionStatus

    func testQuestionStatusDecodesUnknownValue() throws {
        let status = try OperatorJSON.decoder.decode(
            QuestionStatus.self,
            from: Data("\"sometime-future-state\"".utf8)
        )
        XCTAssertEqual(status, .unknown("sometime-future-state"))
        XCTAssertEqual(status.rawValue, "sometime-future-state")
    }

    func testQuestionStatusRoundTrips() throws {
        for status: QuestionStatus in [.draft, .active, .archived, .unknown("custom")] {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(QuestionStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    func testQuestionDefaultsToDraftWhenStatusMissing() throws {
        let json = """
        {
          "id": "44444444-4444-4444-4444-444444444444",
          "prompt": "Legacy question without a status field.",
          "audio": {
            "url": "https://example.com/q.flac",
            "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
            "durationMs": 4321
          },
          "createdAt": "2026-05-23T14:32:11.250Z",
          "retiredAt": null
        }
        """
        let question = try OperatorJSON.decoder.decode(Question.self, from: Data(json.utf8))
        XCTAssertEqual(question.status, .draft)
    }
}
