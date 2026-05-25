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
}
