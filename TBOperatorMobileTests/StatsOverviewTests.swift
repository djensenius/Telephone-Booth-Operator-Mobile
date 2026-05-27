//
//  StatsOverviewTests.swift
//
//  Decode round-trips for /v1/stats/overview, ordered-display helpers,
//  and forward-compatible enum tolerance.
//

import XCTest
@testable import TBOperatorMobile

final class StatsOverviewTests: XCTestCase {

    // MARK: - StatsWindow

    func testStatsWindowRoundTripsKnownAndUnknown() throws {
        for known in StatsWindow.knownCases {
            let encoded = try JSONEncoder().encode(known)
            let decoded = try JSONDecoder().decode(StatsWindow.self, from: encoded)
            XCTAssertEqual(decoded, known)
        }
        let mystery = StatsWindow(rawValue: "future_window")
        XCTAssertEqual(mystery, .unknown("future_window"))
        let data = try JSONEncoder().encode(mystery)
        XCTAssertEqual(try JSONDecoder().decode(StatsWindow.self, from: data), mystery)
        XCTAssertEqual(mystery.rawValue, "future_window")
    }

    // MARK: - Full payload

    func testDecodesFullPayload() throws {
        let json = #"""
        {
          "window": "7d",
          "rangeStart": "2026-05-19T00:00:00Z",
          "rangeEnd": "2026-05-26T00:00:00Z",
          "generatedAt": "2026-05-26T00:00:00Z",
          "timezone": "UTC",
          "calls": {
            "total": 12,
            "completed": 9,
            "inProgress": 1,
            "averageDurationMs": 4321.5,
            "longestDurationMs": 9000,
            "outcomes": {
              "recording_completed": 9,
              "hung_up_before_dial": 2,
              "wild_new_outcome": 1
            },
            "perDay": [
              { "date": "2026-05-25", "total": 5, "completed": 4 },
              { "date": "2026-05-26", "total": 7, "completed": 5 }
            ]
          },
          "messages": {
            "total": 9,
            "byStatus": { "approved": 6, "pending": 2, "rejected": 1 },
            "averageDurationMs": 8500
          },
          "playback": { "totalPlaybacks": 17 },
          "pickupsHangups": {
            "pickups": 12,
            "hangups": 11,
            "digitsDialed": { "1": 3, "5": 5 }
          },
          "uploads": { "succeeded": 9, "failed": 1, "failureRate": 0.1 },
          "topQuestions": [
            {
              "questionId": "11111111-1111-4111-8111-111111111111",
              "prompt": "What did the city sound like today?",
              "messageCount": 5,
              "lastUsedAt": "2026-05-26T00:00:00Z",
              "retiredAt": null
            }
          ],
          "hourly": [
            { "hour": 0, "calls": 0, "messages": 0 },
            { "hour": 10, "calls": 3, "messages": 2 }
          ],
          "busiest": { "hour": 10, "dayOfWeek": 1 },
          "lastActivityAt": "2026-05-26T00:00:00Z",
          "boothBreakdown": [
            { "boothId": "booth-1", "calls": 8, "messages": null, "lastSeenAt": "2026-05-26T00:00:00Z" },
            { "boothId": "booth-2", "calls": 4, "messages": null, "lastSeenAt": "2026-05-25T00:00:00Z" }
          ]
        }
        """#
        let overview = try OperatorJSON.decoder.decode(StatsOverview.self, from: Data(json.utf8))
        XCTAssertEqual(overview.window, .last7d)
        XCTAssertEqual(overview.timezone, "UTC")
        XCTAssertEqual(overview.calls.total, 12)
        XCTAssertEqual(overview.calls.completed, 9)
        XCTAssertEqual(overview.calls.outcomes["wild_new_outcome"], 1)
        XCTAssertEqual(overview.completionRate, 9.0 / 12.0)
        XCTAssertEqual(overview.messages.byStatus["approved"], 6)
        XCTAssertEqual(overview.playback.totalPlaybacks, 17)
        XCTAssertEqual(overview.pickupsHangups.digitsDialed["5"], 5)
        XCTAssertEqual(overview.uploads.failureRate, 0.1)
        XCTAssertEqual(overview.topQuestions.first?.prompt, "What did the city sound like today?")
        XCTAssertEqual(overview.busiest.hour, 10)
        XCTAssertEqual(overview.boothBreakdown.count, 2)
        XCTAssertNil(overview.boothBreakdown.first?.messages)
    }

    // MARK: - Empty payload

    func testDecodesEmptyPayload() throws {
        let json = #"""
        {
          "window": "24h",
          "rangeStart": null,
          "rangeEnd": "2026-05-26T00:00:00Z",
          "generatedAt": "2026-05-26T00:00:00Z",
          "timezone": "UTC",
          "calls": {
            "total": 0,
            "completed": 0,
            "inProgress": 0,
            "averageDurationMs": null,
            "longestDurationMs": null,
            "outcomes": {},
            "perDay": []
          },
          "messages": { "total": 0, "byStatus": {}, "averageDurationMs": null },
          "playback": { "totalPlaybacks": 0 },
          "pickupsHangups": { "pickups": 0, "hangups": 0, "digitsDialed": {} },
          "uploads": { "succeeded": 0, "failed": 0, "failureRate": null },
          "topQuestions": [],
          "hourly": [],
          "busiest": { "hour": null, "dayOfWeek": null },
          "lastActivityAt": null,
          "boothBreakdown": []
        }
        """#
        let overview = try OperatorJSON.decoder.decode(StatsOverview.self, from: Data(json.utf8))
        XCTAssertNil(overview.completionRate)
        XCTAssertNil(overview.rangeStart)
        XCTAssertNil(overview.uploads.failureRate)
        XCTAssertNil(overview.busiest.hour)
        XCTAssertNil(overview.lastActivityAt)
        XCTAssertEqual(overview.calls.outcomes, [:])
        XCTAssertEqual(overview.pickupsHangups.digitsDialed, [:])
    }

    // MARK: - Display helpers

    func testOutcomesInDisplayOrderPutsCanonicalFirstAndUnknownsLast() {
        let calls = StatsOverview.Calls(
            total: 4,
            completed: 2,
            inProgress: 0,
            averageDurationMs: nil,
            longestDurationMs: nil,
            outcomes: [
                "aborted": 1,
                "wild_z_outcome": 2,
                "recording_completed": 2,
                "wild_a_outcome": 1
            ],
            perDay: []
        )
        let overview = makeOverview(calls: calls)
        let ordered = overview.outcomesInDisplayOrder()
        XCTAssertEqual(ordered.map(\.key), [
            "recording_completed",
            "aborted",
            "wild_a_outcome", // sorted asc after canonical
            "wild_z_outcome"
        ])
        XCTAssertEqual(ordered.first?.count, 2)
    }

    func testStatusesInDisplayOrderUsesWorkflowOrder() {
        let messages = StatsOverview.Messages(
            total: 5,
            byStatus: ["approved": 2, "uploading": 1, "pending": 1, "rejected": 1],
            averageDurationMs: nil
        )
        let overview = makeOverview(messages: messages)
        let ordered = overview.statusesInDisplayOrder()
        XCTAssertEqual(ordered.map(\.key), ["uploading", "pending", "approved", "rejected"])
    }

    func testDigitsDialedZeroFilledAlwaysHas10EntriesInOrder() {
        let hangups = StatsOverview.PickupsHangups(
            pickups: 5,
            hangups: 4,
            digitsDialed: ["1": 3, "9": 1]
        )
        let overview = makeOverview(pickupsHangups: hangups)
        let digits = overview.pickupsHangups.digitsDialedZeroFilled()
        XCTAssertEqual(digits.count, 10)
        XCTAssertEqual(digits.map(\.digit), ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
        XCTAssertEqual(digits[1].count, 3)
        XCTAssertEqual(digits[9].count, 1)
        XCTAssertEqual(digits[0].count, 0)
    }

    func testCompletionRateAndQuietForSeconds() {
        let calls = StatsOverview.Calls(
            total: 0,
            completed: 0,
            inProgress: 0,
            averageDurationMs: nil,
            longestDurationMs: nil,
            outcomes: [:],
            perDay: []
        )
        let overview = makeOverview(calls: calls, lastActivityAt: Date(timeIntervalSinceNow: -42))
        XCTAssertNil(overview.completionRate)
        if let seconds = overview.quietForSeconds {
            XCTAssertGreaterThanOrEqual(seconds, 42)
            XCTAssertLessThan(seconds, 45)
        } else {
            XCTFail("quietForSeconds should be non-nil")
        }
    }

    func testDayOfWeekLabelClampsToValidRange() {
        XCTAssertEqual(StatsOverview.dayOfWeekLabel(0), "Sunday")
        XCTAssertEqual(StatsOverview.dayOfWeekLabel(6), "Saturday")
        XCTAssertNil(StatsOverview.dayOfWeekLabel(-1))
        XCTAssertNil(StatsOverview.dayOfWeekLabel(99))
    }

    // MARK: - Helpers

    private func makeOverview(
        calls: StatsOverview.Calls = .init(
            total: 0, completed: 0, inProgress: 0,
            averageDurationMs: nil, longestDurationMs: nil,
            outcomes: [:], perDay: []
        ),
        messages: StatsOverview.Messages = .init(total: 0, byStatus: [:], averageDurationMs: nil),
        pickupsHangups: StatsOverview.PickupsHangups = .init(pickups: 0, hangups: 0, digitsDialed: [:]),
        lastActivityAt: Date? = nil
    ) -> StatsOverview {
        StatsOverview(
            window: .last7d,
            rangeStart: nil,
            rangeEnd: Date(),
            generatedAt: Date(),
            timezone: "UTC",
            calls: calls,
            messages: messages,
            playback: .init(totalPlaybacks: 0),
            pickupsHangups: pickupsHangups,
            uploads: .init(succeeded: 0, failed: 0, failureRate: nil),
            topQuestions: [],
            hourly: [],
            busiest: .init(hour: nil, dayOfWeek: nil),
            lastActivityAt: lastActivityAt,
            boothBreakdown: []
        )
    }
}
