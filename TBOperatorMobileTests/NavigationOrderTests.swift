//
//  NavigationOrderTests.swift
//  TBOperatorMobileTests
//

import XCTest
@testable import TBOperatorMobile

final class NavigationOrderTests: XCTestCase {
    func testRegularOperatorSharedNavigationOrder() {
        XCTAssertEqual(
            OperatorTab.sharedNavigationOrder(isAdmin: false, includesSettings: true),
            [
                .dashboard,
                .stats,
                .sessions,
                .messages,
                .thermals,
                .events,
                .questions,
                .system,
                .settings
            ]
        )
        XCTAssertEqual(
            OperatorTab.sharedNavigationOrder(isAdmin: false, includesSettings: false),
            [
                .dashboard,
                .stats,
                .sessions,
                .messages,
                .thermals,
                .events,
                .questions,
                .system
            ]
        )
    }

    func testAdminSharedNavigationOrder() {
        XCTAssertEqual(
            OperatorTab.sharedNavigationOrder(isAdmin: true, includesSettings: true),
            [
                .dashboard,
                .stats,
                .sessions,
                .messages,
                .thermals,
                .events,
                .questions,
                .instructions,
                .audit,
                .system,
                .settings
            ]
        )
        XCTAssertEqual(
            OperatorTab.sharedNavigationOrder(isAdmin: true, includesSettings: false),
            [
                .dashboard,
                .stats,
                .sessions,
                .messages,
                .thermals,
                .events,
                .questions,
                .instructions,
                .audit,
                .system
            ]
        )
    }

    func testTelevisionNavigationOrderRemainsReadOnly() {
        XCTAssertEqual(
            OperatorTab.televisionNavigationOrder(isAdmin: false),
            [.dashboard, .stats, .sessions, .thermals, .events, .system, .settings]
        )
        XCTAssertEqual(
            OperatorTab.televisionNavigationOrder(isAdmin: true),
            [.dashboard, .stats, .sessions, .thermals, .events, .audit, .system, .settings]
        )
    }

    func testTabIdentifiersRemainStable() {
        XCTAssertEqual(OperatorTab.messages.rawValue, "messages")
        XCTAssertEqual(OperatorTab.thermals.rawValue, "thermals")
    }
}
