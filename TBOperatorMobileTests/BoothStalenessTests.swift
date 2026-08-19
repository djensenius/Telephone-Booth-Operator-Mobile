//
//  BoothStalenessTests.swift
//
//  Tests for shared view helpers.
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

    func testEmptyStatusCopyMatchesConnectionState() {
        XCTAssertEqual(
            BoothStatusLiveStore.ConnectionState.connecting.dashboardEmptyStatusMessage,
            "Connecting to the booth..."
        )
        XCTAssertEqual(
            BoothStatusLiveStore.ConnectionState.offline.dashboardEmptyStatusMessage,
            "Booth status unavailable"
        )
    }
}

final class PaginationRefreshTests: XCTestCase {
    @MainActor
    func testReloadLoadedPagesUsesFreshCursorChain() async throws {
        var requestedCursors: [String?] = []

        let result = try await reloadLoadedPages(
            pageCount: 2,
            isCurrent: { true },
            fetchPage: { cursor in
                requestedCursors.append(cursor)
                if cursor == nil {
                    return ([1, 2], "page-2")
                }
                XCTAssertEqual(cursor, "page-2")
                return ([3, 4], "page-3")
            }
        )

        XCTAssertEqual(requestedCursors.count, 2)
        XCTAssertNil(requestedCursors[0])
        XCTAssertEqual(requestedCursors[1], "page-2")
        XCTAssertEqual(result.items, [1, 2, 3, 4])
        XCTAssertEqual(result.nextCursor, "page-3")
        XCTAssertEqual(result.pageCount, 2)
    }
}
