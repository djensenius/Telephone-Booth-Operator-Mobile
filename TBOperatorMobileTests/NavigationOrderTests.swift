//
//  NavigationOrderTests.swift
//  TBOperatorMobileTests
//

import XCTest
@testable import TBOperatorMobile

final class NavigationOrderTests: XCTestCase {
    func testMessagesPrecedeThermalsWithoutChangingTabIdentifiers() throws {
        let order = OperatorTab.allCases
        let messagesIndex = try XCTUnwrap(order.firstIndex(of: .messages))
        let thermalsIndex = try XCTUnwrap(order.firstIndex(of: .thermals))

        XCTAssertLessThan(messagesIndex, thermalsIndex)
        XCTAssertEqual(OperatorTab.messages.rawValue, "messages")
        XCTAssertEqual(OperatorTab.thermals.rawValue, "thermals")
    }
}
