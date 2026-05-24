//
//  TBOperatorMobileTests.swift
//

import XCTest
@testable import TBOperatorMobile

final class TBOperatorMobileTests: XCTestCase {

    // MARK: - StatsSummary round-trip

    func testStatsSummaryRoundTrip() throws {
        let json = """
        {
          "booth": {
            "state": "playingMessage",
            "updatedAt": "2026-05-23T14:32:11.250Z",
            "currentQuestionId": "11111111-1111-1111-1111-111111111111",
            "currentMessageId": "22222222-2222-2222-2222-222222222222",
            "lastError": null
          },
          "messages": {
            "pending": 3,
            "receivedToday": 12,
            "latestId": "33333333-3333-3333-3333-333333333333"
          },
          "calls": {
            "today": 8,
            "inProgress": 1
          },
          "realtime": {
            "wsClients": 4
          },
          "generatedAt": "2026-05-23T14:32:11.250Z"
        }
        """
        let data = Data(json.utf8)

        let summary = try OperatorJSON.decoder.decode(StatsSummary.self, from: data)
        XCTAssertEqual(summary.booth.state, .playingMessage)
        XCTAssertTrue(summary.booth.state.isCallActive)
        XCTAssertEqual(summary.messages.pending, 3)
        XCTAssertEqual(summary.messages.receivedToday, 12)
        XCTAssertEqual(summary.calls.today, 8)
        XCTAssertEqual(summary.calls.inProgress, 1)
        XCTAssertEqual(summary.realtime.wsClients, 4)

        let reencoded = try OperatorJSON.encoder.encode(summary)
        let again = try OperatorJSON.decoder.decode(StatsSummary.self, from: reencoded)
        XCTAssertEqual(summary, again)
    }

    func testStatsSummaryHandlesBasicISODates() throws {
        let json = """
        {
          "booth": { "state": "idle", "updatedAt": "2026-05-23T14:32:11Z" },
          "messages": { "pending": 0, "receivedToday": 0, "latestId": null },
          "calls": { "today": 0, "inProgress": 0 },
          "realtime": { "wsClients": 0 },
          "generatedAt": "2026-05-23T14:32:11Z"
        }
        """
        let data = Data(json.utf8)

        let summary = try OperatorJSON.decoder.decode(StatsSummary.self, from: data)
        XCTAssertEqual(summary.booth.state, .idle)
        XCTAssertNil(summary.booth.currentQuestionId)
    }

    func testOperatorMeRoundTrip() throws {
        let json = """
        {
          "id": "auth0|operator-1",
          "name": "Ada Lovelace",
          "email": "ada@example.com",
          "groups": ["telephone-booth-operators"],
          "picture": "https://example.com/avatar.png",
          "providerName": "Authentik"
        }
        """
        let data = Data(json.utf8)

        let profile = try OperatorJSON.decoder.decode(OperatorMe.self, from: data)
        XCTAssertEqual(profile.id, "auth0|operator-1")
        XCTAssertEqual(profile.email, "ada@example.com")
        XCTAssertEqual(profile.picture?.host, "example.com")
        XCTAssertEqual(profile.groups, ["telephone-booth-operators"])
    }

    // MARK: - BoothState helpers

    func testBoothStateCallActiveFlags() {
        let active: [BoothState] = [
            .dialing, .playingQuestion, .beep, .recording, .uploading,
            .playingMessage, .playingInstructions
        ]
        let inactive: [BoothState] = [.idle, .dialTone, .error]
        for state in active {
            XCTAssertTrue(state.isCallActive, "\(state) should be call-active")
        }
        for state in inactive {
            XCTAssertFalse(state.isCallActive, "\(state) should not be call-active")
        }
    }

    // MARK: - AppConfig URL building

    func testAppConfigBuildsPathURLs() {
        let url = AppConfig.shared.url(forPath: "/v1/stats/summary")
        XCTAssertEqual(url.path, "/v1/stats/summary")
        XCTAssertEqual(url.scheme, AppConfig.shared.apiBaseURL.scheme)
    }

    func testAppConfigBuildsPathURLsWithoutLeadingSlash() {
        let url = AppConfig.shared.url(forPath: "v1/auth/me")
        XCTAssertEqual(url.path, "/v1/auth/me")
    }
}
