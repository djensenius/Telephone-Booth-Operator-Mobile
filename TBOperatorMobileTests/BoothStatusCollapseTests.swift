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
}
