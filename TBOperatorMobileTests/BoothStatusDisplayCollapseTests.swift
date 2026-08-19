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

    func testActivityCallsGroupAdjacentCallStates() {
        let rows = [
            BoothStatus(state: .idle, updatedAt: now),
            BoothStatus(
                state: .dialing,
                updatedAt: now.addingTimeInterval(10),
                firstSeenAt: now.addingTimeInterval(5)
            ),
            BoothStatus(
                state: .playingQuestion,
                updatedAt: now.addingTimeInterval(25),
                firstSeenAt: now.addingTimeInterval(10)
            ),
            BoothStatus(
                state: .recording,
                updatedAt: now.addingTimeInterval(70),
                firstSeenAt: now.addingTimeInterval(25)
            ),
            BoothStatus(state: .idle, updatedAt: now.addingTimeInterval(75))
        ]

        let calls = rows.activityCalls()

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].startedAt, now.addingTimeInterval(5))
        XCTAssertEqual(calls[0].lastObservedAt, now.addingTimeInterval(75))
        XCTAssertEqual(calls[0].duration(at: now.addingTimeInterval(100)), 70)
        XCTAssertFalse(calls[0].isInProgress)
    }

    func testActivityCallsPreserveInstantCallAndMarkCurrentCallLive() {
        let rows = [
            BoothStatus(state: .idle, updatedAt: now),
            BoothStatus(state: .recording, updatedAt: now),
            BoothStatus(state: .idle, updatedAt: now),
            BoothStatus(
                state: .recording,
                updatedAt: now.addingTimeInterval(15),
                firstSeenAt: now.addingTimeInterval(10)
            )
        ]

        let calls = rows.activityCalls()

        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].duration(at: now.addingTimeInterval(40)), 0)
        XCTAssertFalse(calls[0].isInProgress)
        XCTAssertEqual(calls[1].duration(at: now.addingTimeInterval(40)), 30)
        XCTAssertTrue(calls[1].isInProgress)
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
}
