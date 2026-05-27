//
//  BoothStalenessTests.swift
//
//  Pure-function tests for the booth staleness helper that powers the
//  status badge "Last seen X ago" / "Booth offline" chips.
//

import XCTest
@testable import TBOperatorMobile

final class BoothStalenessTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testNilLastStatusIsTreatedAsFresh() {
        // Production behaviour: nil = no status yet observed, treated as fresh
        // so the chip simply hides. Offline only fires after a real timestamp goes stale.
        let result = boothStaleness(lastStatusAt: nil, now: now)
        XCTAssertEqual(result.level, .fresh)
        XCTAssertNil(result.label)
    }

    func testFreshUnderOneMinute() {
        let result = boothStaleness(lastStatusAt: now.addingTimeInterval(-30), now: now)
        XCTAssertEqual(result.level, .fresh)
        XCTAssertNil(result.label)
    }

    func testWarningBetweenOneMinuteAndFiveMinutes() {
        let oneAndHalf = boothStaleness(lastStatusAt: now.addingTimeInterval(-90), now: now)
        XCTAssertEqual(oneAndHalf.level, .warning)
        let fourMin = boothStaleness(lastStatusAt: now.addingTimeInterval(-240), now: now)
        XCTAssertEqual(fourMin.level, .warning)
    }

    func testOfflineAfterFiveMinutes() {
        let result = boothStaleness(lastStatusAt: now.addingTimeInterval(-301), now: now)
        XCTAssertEqual(result.level, .offline)
        XCTAssertEqual(result.label, "Booth offline")
    }
}
