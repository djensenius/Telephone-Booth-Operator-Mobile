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
