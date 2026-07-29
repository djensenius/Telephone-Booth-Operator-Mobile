//
//  BoothStatusCollapseTests.swift
//
//  The operator collapses identical booth heartbeat reports into one snapshot
//  spanning firstSeenAt..updatedAt with a repeat count. These cover decoding
//  that shape and the "in this state for" label built from it.
//

import XCTest
@testable import TBOperatorMobile

final class BoothStatusCollapseTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func decode(_ json: String) throws -> BoothStatus {
        // Use the app's own decoder so the test exercises the same
        // fractional-seconds date handling as live traffic.
        try OperatorJSON.decoder.decode(BoothStatus.self, from: Data(json.utf8))
    }

    func testDecodesCollapseMetadata() throws {
        let status = try decode("""
        {
            "state": "idle",
            "updatedAt": "2023-11-14T22:13:20.000Z",
            "firstSeenAt": "2023-11-14T22:00:00.000Z",
            "repeatCount": 41
        }
        """)

        XCTAssertEqual(status.repeatCount, 41)
        XCTAssertEqual(status.firstSeenAt, Date(timeIntervalSince1970: 1_699_999_200))
        XCTAssertEqual(status.heldSince, status.firstSeenAt)
    }

    func testFallsBackToUpdatedAtWhenOperatorOmitsMetadata() throws {
        let status = try decode("""
        {
            "state": "idle",
            "updatedAt": "2023-11-14T22:13:20.000Z"
        }
        """)

        XCTAssertNil(status.firstSeenAt)
        XCTAssertNil(status.repeatCount)
        XCTAssertEqual(status.heldSince, status.updatedAt)
    }

    func testHeldForLabelUsesSecondsMinutesAndHours() {
        let seconds = BoothStatus(state: .idle, updatedAt: now, firstSeenAt: now.addingTimeInterval(-42))
        XCTAssertEqual(seconds.heldForLabel(now: now), "42s")

        let minutes = BoothStatus(state: .idle, updatedAt: now, firstSeenAt: now.addingTimeInterval(-600))
        XCTAssertEqual(minutes.heldForLabel(now: now), "10m")

        let hours = BoothStatus(state: .idle, updatedAt: now, firstSeenAt: now.addingTimeInterval(-3840))
        XCTAssertEqual(hours.heldForLabel(now: now), "1h 04m")
    }

    func testHeldForLabelAppendsReportCountOnlyWhenCollapsed() {
        let collapsed = BoothStatus(
            state: .idle,
            updatedAt: now,
            firstSeenAt: now.addingTimeInterval(-600),
            repeatCount: 142
        )
        XCTAssertEqual(collapsed.heldForLabel(now: now), "10m · 142 reports")

        let single = BoothStatus(
            state: .idle,
            updatedAt: now,
            firstSeenAt: now.addingTimeInterval(-600),
            repeatCount: 1
        )
        XCTAssertEqual(single.heldForLabel(now: now), "10m")
    }

    func testHeldForLabelClampsFutureTimestamps() {
        let skewed = BoothStatus(state: .idle, updatedAt: now, firstSeenAt: now.addingTimeInterval(120))
        XCTAssertEqual(skewed.heldForLabel(now: now), "0s")
    }
    // MARK: - Live history merging

    private func run(
        state: BoothState = .idle,
        firstSeenAt: Date,
        updatedAt: Date,
        repeatCount: Int
    ) -> BoothStatus {
        BoothStatus(
            state: state,
            updatedAt: updatedAt,
            firstSeenAt: firstSeenAt,
            repeatCount: repeatCount
        )
    }

    func testRepeatedHeartbeatsReplaceTheCollapsedRunInHistory() {
        let start = now
        var history: [BoothStatus] = []
        for beat in 1...5 {
            let beatAt = start.addingTimeInterval(TimeInterval(beat) * 15)
            history = BoothStatusLiveStore.merging(
                [run(firstSeenAt: start, updatedAt: beatAt, repeatCount: beat)],
                into: history
            )
        }

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.last?.repeatCount, 5)
        XCTAssertEqual(history.last?.updatedAt, start.addingTimeInterval(75))
    }

    func testTransitionsAndLaterRunsStayInHistory() {
        let start = now
        let idle = run(firstSeenAt: start, updatedAt: start.addingTimeInterval(30), repeatCount: 2)
        let recording = run(
            state: .recording,
            firstSeenAt: start.addingTimeInterval(60),
            updatedAt: start.addingTimeInterval(60),
            repeatCount: 1
        )
        let idleAgain = run(
            firstSeenAt: start.addingTimeInterval(90),
            updatedAt: start.addingTimeInterval(90),
            repeatCount: 1
        )

        let history = BoothStatusLiveStore.merging([idle, recording, idleAgain], into: [])

        XCTAssertEqual(history.map(\.state), [.idle, .recording, .idle])
    }

    func testReportsWithoutCollapseMetadataAreKeptSeparately() {
        let first = BoothStatus(state: .idle, updatedAt: now)
        let second = BoothStatus(state: .idle, updatedAt: now.addingTimeInterval(15))

        let history = BoothStatusLiveStore.merging([first, second], into: [])

        XCTAssertEqual(history.count, 2)
    }

    func testDemoStatusIsRebasedOntoTheCallersClock() {
        let reference = Date(timeIntervalSince1970: 2_000_000_000)
        let rebased = DemoData.rebased(DemoData.boothStatus, to: reference)

        XCTAssertEqual(rebased.heldForLabel(now: reference), "1m · 3 reports")
        XCTAssertEqual(
            rebased.updatedAt.timeIntervalSince(rebased.heldSince),
            DemoData.boothStatus.updatedAt.timeIntervalSince(DemoData.boothStatus.heldSince)
        )
    }
    func testStaleRestReportDoesNotRewindAFresherRun() {
        let start = now
        let fresh = run(firstSeenAt: start, updatedAt: start.addingTimeInterval(60), repeatCount: 5)
        let stale = run(firstSeenAt: start, updatedAt: start.addingTimeInterval(30), repeatCount: 3)

        let history = BoothStatusLiveStore.merging([stale], into: [fresh])

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.last?.repeatCount, 5)
        XCTAssertEqual(history.last?.updatedAt, start.addingTimeInterval(60))
    }

    func testDelayedRepeatWideningTheWindowReplacesTheRun() {
        let start = now
        let held = run(
            firstSeenAt: start.addingTimeInterval(30),
            updatedAt: start.addingTimeInterval(30),
            repeatCount: 1
        )
        let widened = run(firstSeenAt: start, updatedAt: start.addingTimeInterval(30), repeatCount: 2)

        let history = BoothStatusLiveStore.merging([widened], into: [held])

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.last?.repeatCount, 2)
        XCTAssertEqual(history.last?.heldSince, start)
    }
    func testEqualTimestampWithLowerRepeatCountIsTreatedAsStale() {
        let start = now
        let widened = run(firstSeenAt: start, updatedAt: start.addingTimeInterval(30), repeatCount: 4)
        let older = run(
            firstSeenAt: start.addingTimeInterval(10),
            updatedAt: start.addingTimeInterval(30),
            repeatCount: 2
        )

        let history = BoothStatusLiveStore.merging([older], into: [widened])

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.last?.repeatCount, 4)
        XCTAssertEqual(history.last?.heldSince, start)
    }

    func testDemoHistoryHasNoCollapsibleNeighbours() {
        let history = DemoData.statusHistory
        for (earlier, later) in zip(history, history.dropFirst()) {
            XCTAssertFalse(earlier.state == later.state, "adjacent \(earlier.state) entries")
        }
    }
    func testTransitionsSharingATimestampAreBothKept() {
        let idle = run(firstSeenAt: now.addingTimeInterval(-30), updatedAt: now, repeatCount: 3)
        let recording = run(
            state: .recording,
            firstSeenAt: now,
            updatedAt: now,
            repeatCount: 1
        )

        let history = BoothStatusLiveStore.merging([idle, recording], into: [])

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(Set(history.map(\.state)), [.idle, .recording])
    }
    func testRunsTouchingAtATransitionTimestampStaySeparate() {
        let start = now
        let boundary = start.addingTimeInterval(30)
        let firstIdle = run(firstSeenAt: start, updatedAt: boundary, repeatCount: 3)
        let recording = run(
            state: .recording,
            firstSeenAt: boundary,
            updatedAt: boundary,
            repeatCount: 1
        )
        let secondIdle = run(
            firstSeenAt: boundary,
            updatedAt: boundary.addingTimeInterval(30),
            repeatCount: 2
        )

        let history = BoothStatusLiveStore.merging([firstIdle, recording, secondIdle], into: [])

        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.map(\.state), [.idle, .recording, .idle])
    }

    func testAShortRunBracketedByIdenticalRunsSurvives() {
        // Everything happens inside one booth millisecond: idle, a blip of
        // recording, idle again. The two idle entries are indistinguishable by
        // value, so only their position keeps them apart.
        let idle = run(firstSeenAt: now, updatedAt: now, repeatCount: 1)
        let recording = run(state: .recording, firstSeenAt: now, updatedAt: now, repeatCount: 1)

        // Delivered one socket frame at a time, so the incremental path is what
        // has to keep them apart.
        var history: [BoothStatus] = []
        for frame in [idle, recording, idle] {
            history = BoothStatusLiveStore.merging([frame], into: history)
        }

        XCTAssertEqual(history.map(\.state), [.idle, .recording, .idle])
    }

    func testRefetchingTheSameHistoryPageIsIdempotent() {
        let instant = now
        let idle = run(firstSeenAt: instant, updatedAt: instant, repeatCount: 1)
        let recording = run(
            state: .recording,
            firstSeenAt: instant,
            updatedAt: instant,
            repeatCount: 1
        )
        let page = [idle, recording, idle]

        let once = BoothStatusLiveStore.merging(page, into: [])
        let twice = BoothStatusLiveStore.merging(page, into: once)

        XCTAssertEqual(twice.map(\.state), [.idle, .recording, .idle])
        XCTAssertEqual(once, twice)
    }

    func testAHistoryPageKeepsAFresherSocketViewOfARun() {
        let held = run(firstSeenAt: now, updatedAt: now.addingTimeInterval(60), repeatCount: 9)
        let stale = run(firstSeenAt: now, updatedAt: now.addingTimeInterval(30), repeatCount: 4)
        let recording = run(
            state: .recording,
            firstSeenAt: now.addingTimeInterval(90),
            updatedAt: now.addingTimeInterval(90),
            repeatCount: 1
        )

        let history = BoothStatusLiveStore.merging([stale, recording], into: [held])

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].repeatCount, 9)
    }

    func testRowIdsTellApartRunsSharingATimestamp() {
        let instant = now
        let first = BoothStatus(
            id: 1,
            state: .idle,
            updatedAt: instant,
            firstSeenAt: instant,
            repeatCount: 9
        )
        let current = BoothStatus(
            id: 3,
            state: .idle,
            updatedAt: instant,
            firstSeenAt: instant,
            repeatCount: 1
        )

        XCTAssertFalse(first.isSameRun(as: current))
        // A delayed frame for the earlier row must not take over the display,
        // however many reports it collapsed.
        XCTAssertTrue(BoothStatusLiveStore.supersedes(current, first))
        XCTAssertFalse(BoothStatusLiveStore.supersedes(first, current))
    }

    func testAFrameMatchesItsCachedRowById() {
        let held = BoothStatus(
            id: 7,
            state: .idle,
            updatedAt: now,
            firstSeenAt: now,
            repeatCount: 2
        )
        let refreshed = BoothStatus(
            id: 7,
            state: .idle,
            updatedAt: now.addingTimeInterval(10),
            firstSeenAt: now,
            repeatCount: 3
        )

        let history = BoothStatusLiveStore.merging([refreshed], into: [held])

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].repeatCount, 3)
    }

    func testAHistoryPageSharingATimestampIsOrderedByRowId() {
        let instant = now
        let row = { (id: Int, state: BoothState) in
            BoothStatus(
                id: id,
                state: state,
                updatedAt: instant,
                firstSeenAt: instant,
                repeatCount: 1
            )
        }
        // The REST endpoint returns newest first, ties broken by descending id.
        let page = [row(3, .idle), row(2, .recording), row(1, .idle)]

        let history = BoothStatusLiveStore.merging(page, into: [])

        XCTAssertEqual(history.map(\.id), [1, 2, 3])
    }

    func testAPageKeepsASocketRowSharingItsNewestTimestamp() {
        let instant = now
        let page = [
            BoothStatus(id: 1, state: .idle, updatedAt: instant, firstSeenAt: instant),
            BoothStatus(
                id: 2,
                state: .recording,
                updatedAt: instant.addingTimeInterval(-10),
                firstSeenAt: instant.addingTimeInterval(-10)
            )
        ]
        // Delivered by the socket while the page was in flight.
        let live = BoothStatus(id: 3, state: .beep, updatedAt: instant, firstSeenAt: instant)

        let history = BoothStatusLiveStore.merging(page, into: [live])

        XCTAssertEqual(history.map(\.id), [2, 1, 3])
    }

    func testAPageDoesNotDuplicateARunTheSocketHasAdvanced() {
        let start = now
        let held = BoothStatus(
            id: 1,
            state: .idle,
            updatedAt: start.addingTimeInterval(60),
            firstSeenAt: start,
            repeatCount: 6
        )
        // The page was generated before that heartbeat reached the socket.
        let stale = BoothStatus(
            id: 1,
            state: .idle,
            updatedAt: start.addingTimeInterval(30),
            firstSeenAt: start,
            repeatCount: 3
        )
        let earlier = BoothStatus(
            id: 0,
            state: .recording,
            updatedAt: start.addingTimeInterval(-10),
            firstSeenAt: start.addingTimeInterval(-10)
        )

        let history = BoothStatusLiveStore.merging([earlier, stale], into: [held])

        XCTAssertEqual(history.map(\.id), [0, 1])
        XCTAssertEqual(history[1].repeatCount, 6)
    }

    func testRowsWithoutAnIdSortBeforeIdentifiedRowsOfTheSameInstant() {
        let instant = now
        let legacy = BoothStatus(state: .idle, updatedAt: instant)
        let first = BoothStatus(id: 1, state: .recording, updatedAt: instant, firstSeenAt: instant)
        let second = BoothStatus(id: 2, state: .beep, updatedAt: instant, firstSeenAt: instant)

        let history = BoothStatusLiveStore.merging([second, first, legacy], into: [])

        XCTAssertEqual(history.map(\.state), [.idle, .recording, .beep])
    }

    func testAPageKeepsARowInsertedAfterItWasGenerated() {
        let start = now
        let older = BoothStatus(
            id: 1,
            state: .idle,
            updatedAt: start,
            firstSeenAt: start
        )
        let newer = BoothStatus(
            id: 2,
            state: .idle,
            updatedAt: start.addingTimeInterval(60),
            firstSeenAt: start.addingTimeInterval(60)
        )
        // Broadcast while the page request was in flight: reported between the
        // page's entries, but recorded after the page was generated.
        let delayed = BoothStatus(
            id: 3,
            state: .recording,
            updatedAt: start.addingTimeInterval(30),
            firstSeenAt: start.addingTimeInterval(30)
        )

        let history = BoothStatusLiveStore.merging([newer, older], into: [delayed])

        XCTAssertEqual(history.map(\.id), [1, 3, 2])
    }

    func testLegacyReportsNeverMatchACollapsedRun() {
        let collapsed = run(firstSeenAt: now, updatedAt: now.addingTimeInterval(60), repeatCount: 5)
        let legacy = BoothStatus(state: .idle, updatedAt: now.addingTimeInterval(30))

        XCTAssertFalse(collapsed.isSameRun(as: legacy))
        XCTAssertFalse(legacy.isSameRun(as: collapsed))
        XCTAssertEqual(BoothStatusLiveStore.merging([legacy], into: [collapsed]).count, 2)
    }
}
