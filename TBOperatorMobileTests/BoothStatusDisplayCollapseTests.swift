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
}
