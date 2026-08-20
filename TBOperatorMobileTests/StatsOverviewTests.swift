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
          "rangeStart": "2026-05-19T00:00:00Z", "rangeEnd": "2026-05-26T00:00:00Z",
          "generatedAt": "2026-05-26T00:00:00Z", "timezone": "UTC",
          "calls": {
            "total": 12, "completed": 9, "inProgress": 1,
            "averageDurationMs": 4321.5, "longestDurationMs": 9000,
            "outcomes": { "recording_completed": 9, "hung_up_before_dial": 2, "wild_new_outcome": 1 },
            "perDay": [{ "date": "2026-05-25", "total": 5, "completed": 4 },
              { "date": "2026-05-26", "total": 7, "completed": 5 }]
          },
          "interactions": {
            "total": 12, "inProgressNow": 1, "noSelection": 2, "messagesLeft": 8,
            "averageDurationMs": 5123.5, "longestDurationMs": 9100,
            "outcomes": { "recording_completed": 8, "hung_up_before_dial": 2, "wild_new_outcome": 2 },
            "perDay": [
              { "date": "2026-05-25", "total": 5, "noSelection": 1, "messagesLeft": 3 },
              { "date": "2026-05-26", "total": 7, "noSelection": 1, "messagesLeft": 5 }
            ]
          },
          "actions": {
            "digitsDialed": { "0": 1, "1": 4, "2": 3, "3": 2, "8": 1 },
            "leaveMessageSelections": 4,
            "listenMessageSelections": 3,
            "instructionSelections": 1,
            "wrongNumberAttempts": 3,
            "messagePlaybackStarts": 2,
            "instructionPlaybackStarts": 1
          },
          "messages": { "total": 6, "approved": 6, "allRecordings": 9,
            "byStatus": { "approved": 6, "pending": 2, "rejected": 1 },
            "averageDurationMs": 8500 },
          "playback": { "totalPlaybacks": 17 },
          "pickupsHangups": { "pickups": 12, "hangups": 11, "digitsDialed": { "1": 3, "5": 5 } },
          "uploads": { "succeeded": 9, "failed": 1, "failureRate": 0.1 },
          "topQuestions": [{
            "questionId": "11111111-1111-4111-8111-111111111111",
            "prompt": "What did the city sound like today?",
            "messageCount": 5, "lastUsedAt": "2026-05-26T00:00:00Z", "retiredAt": null
          }],
          "hourly": [{ "hour": 0, "calls": 0, "interactions": 0, "messages": 0 },
            { "hour": 10, "calls": 3, "interactions": 4, "messages": 2 }],
          "busiest": { "hour": 10, "dayOfWeek": 1 },
          "lastActivityAt": "2026-05-26T00:00:00Z",
          "boothBreakdown": [
            {
              "boothId": "booth-1",
              "calls": 8,
              "interactions": 8,
              "messages": null,
              "lastSeenAt": "2026-05-26T00:00:00Z"
            },
            {
              "boothId": "booth-2",
              "calls": 4,
              "interactions": 5,
              "messages": null,
              "lastSeenAt": "2026-05-25T00:00:00Z"
            }
          ]
        }
        """#
        let overview = try OperatorJSON.decoder.decode(StatsOverview.self, from: Data(json.utf8))
        XCTAssertEqual(overview.window, .last7d)
        XCTAssertEqual(overview.timezone, "UTC")
        XCTAssertEqual(overview.calls.total, 12)
        XCTAssertEqual(overview.calls.completed, 9)
        XCTAssertEqual(overview.interactions?.messagesLeft, Optional(8))
        XCTAssertEqual(overview.interactionMetrics.messagesLeft, 8)
        XCTAssertEqual(overview.calls.outcomes["wild_new_outcome"], 1)
        XCTAssertEqual(overview.completionRate, 8.0 / 12.0)
        XCTAssertEqual(overview.outcomesInDisplayOrder().first?.count, 8)
        XCTAssertEqual(overview.messages.byStatus["approved"], 6)
        XCTAssertEqual(overview.messages.approvedCount, 6)
        XCTAssertEqual(overview.messages.allRecordingsCount, 9)
        XCTAssertEqual(overview.actionMetrics.leaveMessageSelections, 4)
        XCTAssertEqual(overview.actionMetrics.wrongNumberAttempts, 3)
        XCTAssertEqual(overview.actionMetrics.messagePlaybackStarts, Optional(2))
        XCTAssertEqual(overview.playback.totalPlaybacks, 17)
        XCTAssertEqual(overview.pickupsHangups.digitsDialed["5"], 5)
        XCTAssertEqual(overview.uploads.failureRate, 0.1)
        XCTAssertEqual(overview.topQuestions.first?.prompt, "What did the city sound like today?")
        XCTAssertEqual(overview.busiest.hour, 10)
        XCTAssertEqual(overview.boothBreakdown.count, 2)
        XCTAssertEqual(overview.hourly[1].interactionCount, 4)
        XCTAssertEqual(overview.boothBreakdown[1].interactionCount, 5)
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
        XCTAssertEqual(overview.interactionMetrics.total, 0)
        XCTAssertEqual(overview.actionMetrics.wrongNumberAttempts, 0)
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

    func testMessageCountsFallBackForRollingDeployment() {
        let messages = StatsOverview.Messages(
            total: 5,
            byStatus: ["approved": 5],
            averageDurationMs: nil
        )
        XCTAssertEqual(messages.approvedCount, 5)
        XCTAssertEqual(messages.allRecordingsCount, 5)
    }

    func testApprovedCountPrefersStatusForLegacyResponse() {
        let messages = StatsOverview.Messages(
            total: 9,
            byStatus: ["approved": 6, "pending": 2, "rejected": 1],
            averageDurationMs: nil
        )

        XCTAssertEqual(messages.approvedCount, 6)
        XCTAssertEqual(messages.allRecordingsCount, 9)
    }

    func testLegacyOverviewFallsBackToInteractionAndActionMetrics() {
        let calls = StatsOverview.Calls(
            total: 9,
            completed: 4,
            inProgress: 2,
            averageDurationMs: 12_000,
            longestDurationMs: 30_000,
            outcomes: [
                "recording_completed": 4,
                "hung_up_before_dial": 3,
                "upload_failed": 2
            ],
            perDay: [
                .init(date: "2026-08-18", total: 5, completed: 2),
                .init(date: "2026-08-19", total: 4, completed: 2)
            ]
        )
        let overview = makeOverview(
            calls: calls,
            playback: .init(totalPlaybacks: 7),
            pickupsHangups: .init(
                pickups: 9,
                hangups: 7,
                digitsDialed: ["0": 2, "1": 4, "2": 3, "3": 1, "9": 2]
            )
        )

        XCTAssertNil(overview.interactions)
        XCTAssertEqual(overview.interactionMetrics.messagesLeft, 4)
        XCTAssertEqual(overview.interactionMetrics.noSelection, 3)
        XCTAssertEqual(overview.completionRate, 4.0 / 9.0)
        XCTAssertEqual(overview.interactionMetrics.perDay[0].messagesLeftCount, 2)
        XCTAssertEqual(overview.actionMetrics.leaveMessageSelections, 4)
        XCTAssertEqual(overview.actionMetrics.listenMessageSelections, 3)
        XCTAssertEqual(overview.actionMetrics.instructionSelections, 2)
        XCTAssertEqual(overview.actionMetrics.wrongNumberAttempts, 3)
        XCTAssertNil(overview.actionMetrics.messagePlaybackStarts)
        XCTAssertEqual(overview.actionMetrics.totalPlaybackStarts, Optional(7))
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
        interactions: StatsOverview.Interactions? = nil,
        actions: StatsOverview.Actions? = nil,
        messages: StatsOverview.Messages = .init(total: 0, byStatus: [:], averageDurationMs: nil),
        playback: StatsOverview.Playback = .init(totalPlaybacks: 0),
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
            interactions: interactions,
            actions: actions,
            messages: messages,
            playback: playback,
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

final class AdaptiveStatsLayoutTests: XCTestCase {
    func testEmptyArrangementHasNoFramesOrSize() {
        let arrangement = StatsSectionColumnsLayout.arrangement(for: [], availableWidth: 900)

        XCTAssertEqual(arrangement.containerSize, .zero)
        XCTAssertTrue(arrangement.frames.isEmpty)
    }

    func testUsesTwoColumnsOnlyForFiniteWideWidthsWithMultipleSections() {
        XCTAssertFalse(StatsSectionColumnsLayout.usesTwoColumns(availableWidth: nil, itemCount: 6))
        XCTAssertFalse(StatsSectionColumnsLayout.usesTwoColumns(availableWidth: .infinity, itemCount: 6))
        XCTAssertFalse(StatsSectionColumnsLayout.usesTwoColumns(availableWidth: 899, itemCount: 6))
        XCTAssertTrue(StatsSectionColumnsLayout.usesTwoColumns(availableWidth: 900, itemCount: 6))
        XCTAssertFalse(StatsSectionColumnsLayout.usesTwoColumns(availableWidth: 1_200, itemCount: 1))
    }

    func testTwoColumnArrangementKeepsStableEvenOddAssignments() {
        let arrangement = StatsSectionColumnsLayout.arrangement(
            for: [
                CGSize(width: 320, height: 100),
                CGSize(width: 320, height: 40),
                CGSize(width: 320, height: 30),
                CGSize(width: 320, height: 80),
                CGSize(width: 320, height: 20)
            ],
            availableWidth: 900
        )

        XCTAssertEqual(arrangement.containerSize, CGSize(width: 900, height: 182))
        XCTAssertEqual(arrangement.frames, [
            CGRect(x: 0, y: 0, width: 442, height: 100),
            CGRect(x: 458, y: 0, width: 442, height: 40),
            CGRect(x: 0, y: 116, width: 442, height: 30),
            CGRect(x: 458, y: 56, width: 442, height: 80),
            CGRect(x: 0, y: 162, width: 442, height: 20)
        ])
    }

    func testArrangementUpdatesForChangedHeightsAtSameWidthAndCount() {
        let initial = StatsSectionColumnsLayout.arrangement(
            for: [
                CGSize(width: 320, height: 100),
                CGSize(width: 320, height: 40),
                CGSize(width: 320, height: 30),
                CGSize(width: 320, height: 80)
            ],
            availableWidth: 900
        )
        let updated = StatsSectionColumnsLayout.arrangement(
            for: [
                CGSize(width: 320, height: 140),
                CGSize(width: 320, height: 60),
                CGSize(width: 320, height: 90),
                CGSize(width: 320, height: 20)
            ],
            availableWidth: 900
        )

        XCTAssertEqual(initial.containerSize, CGSize(width: 900, height: 146))
        XCTAssertEqual(initial.frames, [
            CGRect(x: 0, y: 0, width: 442, height: 100),
            CGRect(x: 458, y: 0, width: 442, height: 40),
            CGRect(x: 0, y: 116, width: 442, height: 30),
            CGRect(x: 458, y: 56, width: 442, height: 80)
        ])
        XCTAssertEqual(updated.containerSize, CGSize(width: 900, height: 246))
        XCTAssertEqual(updated.frames, [
            CGRect(x: 0, y: 0, width: 442, height: 140),
            CGRect(x: 458, y: 0, width: 442, height: 60),
            CGRect(x: 0, y: 156, width: 442, height: 90),
            CGRect(x: 458, y: 76, width: 442, height: 20)
        ])
    }

    func testSingleColumnArrangementPreservesSourceOrderWhenWidthIsUnknown() {
        let arrangement = StatsSectionColumnsLayout.arrangement(
            for: [
                CGSize(width: 220, height: 60),
                CGSize(width: 260, height: 110),
                CGSize(width: 240, height: 80)
            ],
            availableWidth: nil
        )

        XCTAssertEqual(arrangement.containerSize, CGSize(width: 260, height: 282))
        XCTAssertEqual(arrangement.frames, [
            CGRect(x: 0, y: 0, width: 220, height: 60),
            CGRect(x: 0, y: 76, width: 260, height: 110),
            CGRect(x: 0, y: 202, width: 240, height: 80)
        ])
    }
}
