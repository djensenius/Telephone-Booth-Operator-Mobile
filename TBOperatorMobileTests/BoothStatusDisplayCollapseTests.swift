//
//  BoothStatusDisplayCollapseTests.swift
//
//  Rows recorded before the operator collapsed on write are one per
//  heartbeat, so the console folds them again at display time.
//

import XCTest
@testable import TBOperatorMobile

final class BoothStatusDisplayCollapseTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testLegacyHeartbeatRowsCollapseForDisplay() {
        // Pre-migration rows: one per heartbeat, each its own snapshot.
        let rows = (0..<40).map { index in
            BoothStatus(id: index, state: .idle, updatedAt: now.addingTimeInterval(Double(index) * 5))
        } + [BoothStatus(id: 40, state: .recording, updatedAt: now.addingTimeInterval(200))]

        let display = rows.collapsingRepeats()

        XCTAssertEqual(display.map(\.state), [.idle, .recording])
        XCTAssertEqual(display[0].repeatCount, 40)
        XCTAssertEqual(display[0].heldSince, now)
        XCTAssertEqual(display[0].updatedAt, now.addingTimeInterval(195))
    }

    func testDisplayCollapseKeepsAStatusThatRecurs() {
        let rows = [
            BoothStatus(id: 1, state: .idle, updatedAt: now),
            BoothStatus(id: 2, state: .recording, updatedAt: now.addingTimeInterval(5)),
            BoothStatus(id: 3, state: .idle, updatedAt: now.addingTimeInterval(10))
        ]

        XCTAssertEqual(rows.collapsingRepeats().map(\.id), [1, 2, 3])
    }

    func testCallsTodaySeriesUsesRealSessionsOnceAndOrdersSteps() {
        let dayStartedAt = now
        let through = now.addingTimeInterval(100)
        let sessions = [
            session(id: "b", startedAt: now.addingTimeInterval(20)),
            session(id: "a", startedAt: now.addingTimeInterval(10)),
            session(id: "c", startedAt: now.addingTimeInterval(20)),
            session(id: "a", startedAt: now.addingTimeInterval(30)),
            session(id: "old", startedAt: now.addingTimeInterval(-1)),
            session(id: "future", startedAt: now.addingTimeInterval(101))
        ]

        let series = CallsTodaySeries(
            sessions: sessions,
            dayStartedAt: dayStartedAt,
            now: through
        )

        XCTAssertEqual(series.total, 3)
        XCTAssertEqual(series.points.map(\.date), [
            dayStartedAt,
            now.addingTimeInterval(10),
            now.addingTimeInterval(20),
            through
        ])
        XCTAssertEqual(series.points.map(\.count), [0, 1, 3, 3])
    }

    func testCallsTodaySeriesIncludesExactMidnightAndHandlesNoCalls() {
        let through = now.addingTimeInterval(60)
        let midnight = CallsTodaySeries(
            sessions: [session(id: "midnight", startedAt: now)],
            dayStartedAt: now,
            now: through
        )
        let empty = CallsTodaySeries(
            sessions: [session(id: "before", startedAt: now.addingTimeInterval(-0.001))],
            dayStartedAt: now,
            now: through
        )

        XCTAssertEqual(midnight.total, 1)
        XCTAssertEqual(midnight.points.map(\.count), [1, 1])
        XCTAssertEqual(empty.total, 0)
        XCTAssertEqual(empty.points.map(\.count), [0, 0])
        XCTAssertEqual(empty.yAxisValues, [0, 1])
    }

    func testCallsTodayPaginationStopsAfterCrossingDayBoundary() {
        var pages = CallsTodayPageAccumulator(dayStartedAt: now)
        let firstCursor = pages.append(SessionListPage(
            items: [
                session(id: "newest", startedAt: now.addingTimeInterval(20)),
                session(id: "middle", startedAt: now.addingTimeInterval(10))
            ],
            nextCursor: "page-2"
        ))
        let secondCursor = pages.append(SessionListPage(
            items: [
                session(id: "midnight", startedAt: now),
                session(id: "yesterday", startedAt: now.addingTimeInterval(-1))
            ],
            nextCursor: "page-3"
        ))

        XCTAssertEqual(firstCursor, "page-2")
        XCTAssertNil(secondCursor)
        XCTAssertEqual(pages.orderedSessions.map(\.id), ["midnight", "middle", "newest"])
    }

    func testCallsTodayPaginationStopsAtCachedSessionOverlap() {
        var pages = CallsTodayPageAccumulator(
            dayStartedAt: now,
            knownSessionIDs: ["cached"]
        )
        let cursor = pages.append(SessionListPage(
            items: [
                session(id: "new", startedAt: now.addingTimeInterval(20)),
                session(id: "cached", startedAt: now.addingTimeInterval(10))
            ],
            nextCursor: "unneeded-page"
        ))

        XCTAssertNil(cursor)
        XCTAssertEqual(pages.orderedSessions.map(\.id), ["cached", "new"])
    }

    func testDemoCallsTodayCountMatchesSummary() throws {
        let summary = DemoData.rebasedStats(to: DemoData.sessionAnchor)
        let start = try XCTUnwrap(summary.dayStartedAt)
        let series = CallsTodaySeries(
            sessions: DemoData.rebasedSessions(),
            dayStartedAt: start,
            now: DemoData.sessionAnchor
        )

        XCTAssertEqual(series.total, summary.calls.today)
    }

    func testDemoSessionEventsShareTheRebasedSessionTimeline() {
        let detail = DemoData.sessionDetail(id: "demo-session-2")

        XCTAssertFalse(detail.events.isEmpty)
        XCTAssertTrue(detail.events.allSatisfy { $0.occurredAt >= detail.startedAt })
        XCTAssertTrue(detail.events.allSatisfy { event in
            detail.endedAt.map { event.occurredAt <= $0 } ?? true
        })
    }

    func testIdLessRunReturningAfterATransitionIsKept() {
        // A collapsed operator that sends no row id: idle, a blip of recording,
        // idle again, all inside one booth millisecond.
        let instant = now
        let first = BoothStatus(
            state: .idle, updatedAt: instant,
            firstSeenAt: instant.addingTimeInterval(-30), repeatCount: 3
        )
        let blip = BoothStatus(state: .recording, updatedAt: instant, firstSeenAt: instant)
        let second = BoothStatus(state: .idle, updatedAt: instant, firstSeenAt: instant)

        let history = BoothStatusLiveStore.merging([second], into: [first, blip])

        XCTAssertEqual(history.map(\.state), [.idle, .recording, .idle])
    }

    func testPageDoesNotClaimAnIdLessRunItNeverSaw() {
        let instant = now
        let earlier = BoothStatus(
            state: .idle, updatedAt: instant,
            firstSeenAt: instant.addingTimeInterval(-30), repeatCount: 3
        )
        let blip = BoothStatus(state: .recording, updatedAt: instant, firstSeenAt: instant)
        // Delivered by the socket while the page was in flight.
        let latest = BoothStatus(state: .idle, updatedAt: instant, firstSeenAt: instant)

        let history = BoothStatusLiveStore.merging([blip, earlier], into: [earlier, blip, latest])

        XCTAssertEqual(history.map(\.state), [.idle, .recording, .idle])
    }

    func testCompactStatusDurationFormatting() {
        XCTAssertEqual(
            DurationFormatter.compactString(from: now, to: now.addingTimeInterval(42)),
            "42s"
        )
        XCTAssertEqual(
            DurationFormatter.compactString(from: now, to: now.addingTimeInterval(3_840)),
            "1h 4m"
        )
        XCTAssertEqual(
            DurationFormatter.compactString(from: now, to: now.addingTimeInterval(93_600)),
            "1d 2h"
        )
        XCTAssertEqual(
            DurationFormatter.compactString(from: now, to: now.addingTimeInterval(-60)),
            "0s"
        )
    }

    private func session(id: String, startedAt: Date) -> CallSession {
        CallSession(
            id: id,
            boothId: "booth",
            bootId: "boot",
            startedAt: startedAt,
            endedAt: nil,
            digitsDialed: nil,
            outcome: nil,
            recordingId: nil,
            durationMs: nil
        )
    }
}

final class StatsSummaryDayBoundaryTests: XCTestCase {

    func testDayBoundaryMetadataRoundTripsAndRemainsOptional() throws {
        let dayStartedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = StatsSummary(
            booth: BoothStatus(state: .idle, updatedAt: dayStartedAt),
            messages: StatsSummary.Messages(
                pending: 0,
                receivedToday: 0,
                latestId: nil
            ),
            calls: StatsSummary.Calls(today: 0, inProgress: 0),
            interactions: StatsSummary.Calls(today: 0, inProgress: 0),
            realtime: StatsSummary.Realtime(wsClients: 0),
            generatedAt: dayStartedAt,
            dayStartedAt: dayStartedAt,
            timeZone: "America/Toronto"
        )

        let data = try OperatorJSON.encoder.encode(summary)
        let decoded = try OperatorJSON.decoder.decode(StatsSummary.self, from: data)

        XCTAssertEqual(decoded.dayStartedAt, dayStartedAt)
        XCTAssertEqual(decoded.timeZone, "America/Toronto")
        XCTAssertEqual(decoded.interactionsToday, 0)
        XCTAssertNil(StatsSummary.placeholder.dayStartedAt)
        XCTAssertNil(StatsSummary.placeholder.timeZone)
    }
}

final class StatsSummaryCompatibilityTests: XCTestCase {
    func testStatsSummaryPrefersAdditiveInteractionsWhenPresent() throws {
        let json = """
        {
          "booth": { "state": "idle", "updatedAt": "2026-05-23T14:32:11Z" },
          "messages": { "pending": 0, "receivedToday": 0, "latestId": null },
          "calls": { "today": 2, "inProgress": 0 },
          "interactions": { "today": 5, "inProgress": 3 },
          "realtime": { "wsClients": 1 },
          "generatedAt": "2026-05-23T14:32:11Z"
        }
        """

        let summary = try OperatorJSON.decoder.decode(StatsSummary.self, from: Data(json.utf8))
        XCTAssertEqual(summary.calls.today, 2)
        XCTAssertEqual(summary.interactions?.today, Optional(5))
        XCTAssertEqual(summary.interactionsToday, 5)
        XCTAssertEqual(summary.interactionsInProgress, 3)
    }
}

@MainActor
final class BoothStatusLiveStoreCompatibilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testApplyingSummaryPreservesAdditiveInteractions() throws {
        let store = BoothStatusLiveStore()
        store.applyStats(makeSummary(booth: BoothStatus(state: .idle, updatedAt: now)))

        let stats = try XCTUnwrap(store.stats)
        XCTAssertEqual(stats.calls.today, 2)
        XCTAssertEqual(stats.interactions?.today, 5)
        XCTAssertEqual(stats.interactionsToday, 5)
        XCTAssertEqual(stats.interactionsInProgress, 3)
    }

    func testStatusUpdatesKeepAdditiveInteractionsFromCurrentSummary() throws {
        let store = BoothStatusLiveStore()
        store.applyStats(makeSummary(booth: BoothStatus(state: .idle, updatedAt: now)))

        store.applyStatusForTesting(
            BoothStatus(state: .recording, updatedAt: now.addingTimeInterval(60))
        )

        let stats = try XCTUnwrap(store.stats)
        XCTAssertEqual(stats.booth.state, .recording)
        XCTAssertEqual(stats.calls.today, 2)
        XCTAssertEqual(stats.interactions?.today, 5)
        XCTAssertEqual(stats.interactionsToday, 5)
        XCTAssertEqual(stats.interactionsInProgress, 3)
    }

    private func makeSummary(booth: BoothStatus) -> StatsSummary {
        StatsSummary(
            booth: booth,
            messages: StatsSummary.Messages(
                pending: 1,
                receivedToday: 1,
                latestId: nil
            ),
            calls: .init(today: 2, inProgress: 0),
            interactions: .init(today: 5, inProgress: 3),
            realtime: .init(wsClients: 1),
            generatedAt: now
        )
    }
}

final class WidgetSnapshotCompatibilityTests: XCTestCase {
    func testWidgetSnapshotFromStatsSummary() {
        let stats = StatsSummary(
            booth: StatsSummary.placeholder.booth,
            messages: StatsSummary.placeholder.messages,
            calls: .init(today: 4, inProgress: 0),
            interactions: .init(today: 9, inProgress: 2),
            realtime: StatsSummary.placeholder.realtime,
            generatedAt: StatsSummary.placeholder.generatedAt
        )
        let snapshot = WidgetSnapshot(stats: stats)
        XCTAssertEqual(snapshot.boothState, stats.booth.state)
        XCTAssertEqual(snapshot.boothUpdatedAt, stats.booth.updatedAt)
        XCTAssertEqual(snapshot.pendingMessages, stats.messages.pending)
        XCTAssertEqual(snapshot.receivedToday, stats.messages.receivedToday)
        XCTAssertEqual(snapshot.callsToday, stats.interactionsToday)
        XCTAssertEqual(snapshot.callsInProgress, stats.interactionsInProgress)
        XCTAssertEqual(snapshot.interactionsToday, 9)
        XCTAssertEqual(snapshot.interactionsInProgress, 2)
        XCTAssertEqual(snapshot.wsClients, stats.realtime.wsClients)
        XCTAssertEqual(snapshot.generatedAt, stats.generatedAt)
    }
}

final class InstallationCompatibilityTests: XCTestCase {
    func testInstallationScopeQueryValues() {
        XCTAssertNil(InstallationScope.current.queryValue)
        XCTAssertEqual(InstallationScope.all.queryValue, "all")
        XCTAssertEqual(
            InstallationScope.installation("era-1").queryValue,
            "era-1"
        )
    }

    func testInstallationDecodesWithoutLanguageDuringDeployment() throws {
        let installation = try OperatorJSON.decoder.decode(
            Installation.self,
            from: Data(#"""
            {
              "id":"00000000-0000-4000-8000-000000000001",
              "name":"Opening",
              "notes":null,
              "location":null,
              "startedAt":"2026-08-14T12:00:00Z",
              "endedAt":null,
              "endedById":null,
              "summary":null,
              "createdAt":"2026-08-14T12:00:00Z",
              "isActive":true
            }
            """#.utf8)
        )
        XCTAssertNil(installation.defaultTranscriptionLanguage)
        XCTAssertTrue(installation.isActive)
    }
}
