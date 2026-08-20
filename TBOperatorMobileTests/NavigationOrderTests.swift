//
//  NavigationOrderTests.swift
//  TBOperatorMobileTests
//

import XCTest
@testable import TBOperatorMobile

final class NavigationOrderTests: XCTestCase {
    func testReviewFilterIncludesReceivedAndPendingMessages() {
        XCTAssertTrue(MessageListFilter.review.includes(.received))
        XCTAssertTrue(MessageListFilter.review.includes(.pending))
        XCTAssertFalse(MessageListFilter.review.includes(.approved))
        XCTAssertEqual(MessageListFilter.review.requestedStatuses, [.received, .pending])
    }

    func testParsesSupportedAppNavigationURLs() throws {
        let dashboard = try XCTUnwrap(URL(string: "tboperator://dashboard"))
        let stats = try XCTUnwrap(URL(string: "tboperator://stats"))
        let sessions = try XCTUnwrap(URL(string: "tboperator://sessions"))
        let sessionDetail = try XCTUnwrap(URL(string: "tboperator://sessions/session%2D123"))
        let messages = try XCTUnwrap(URL(string: "tboperator://messages"))
        let messageDetail = try XCTUnwrap(URL(string: "tboperator://messages/message%2D123"))
        let review = try XCTUnwrap(URL(string: "tboperator://messages?filter=review"))
        let legacyReview = try XCTUnwrap(URL(string: "tboperator://messages?filter=received"))
        let thermals = try XCTUnwrap(URL(string: "tboperator://thermals"))
        let system = try XCTUnwrap(URL(string: "tboperator://system"))

        XCTAssertEqual(AppNavigationTarget(url: dashboard), .dashboard)
        XCTAssertEqual(AppNavigationTarget(url: stats), .stats)
        XCTAssertEqual(AppNavigationTarget(url: sessions), .sessions)
        XCTAssertEqual(AppNavigationTarget(url: sessionDetail), .session(id: "session-123"))
        XCTAssertEqual(AppNavigationTarget(url: messages), .messages(.list(filter: .all)))
        XCTAssertEqual(AppNavigationTarget(url: messageDetail), .messages(.detail(id: "message-123")))
        XCTAssertEqual(AppNavigationTarget(url: review), .messages(.list(filter: .review)))
        XCTAssertEqual(AppNavigationTarget(url: legacyReview), .messages(.list(filter: .review)))
        XCTAssertEqual(AppNavigationTarget(url: thermals), .thermals)
        XCTAssertEqual(AppNavigationTarget(url: system), .system)
    }

    func testAppNavigationParserRejectsForeignAndMalformedURLs() throws {
        let urls = try [
            XCTUnwrap(URL(string: "https://dashboard")),
            XCTUnwrap(URL(string: "tboperator://unknown")),
            XCTUnwrap(URL(string: "tboperator://messages?filter=unsupported")),
            XCTUnwrap(URL(string: "tboperator://messages?filter=review&filter=received")),
            XCTUnwrap(URL(string: "tboperator://messages/message%2F123")),
            XCTUnwrap(URL(string: "tboperator://messages/.")),
            XCTUnwrap(URL(string: "tboperator://messages/..")),
            XCTUnwrap(URL(string: "tboperator://sessions/%2E%2E")),
            XCTUnwrap(URL(string: "tboperator://sessions/")),
            XCTUnwrap(URL(string: "tboperator://sessions/session-123/extra")),
            XCTUnwrap(URL(string: "tboperator://dashboard#fragment"))
        ]

        XCTAssertTrue(urls.allSatisfy { AppNavigationTarget(url: $0) == nil })
    }

    @MainActor
    func testNavigationStorePreservesOnePendingTargetAndConsumesIt() throws {
        let store = AppNavigationStore()
        store.route(to: .dashboard)
        let generation = store.routeGeneration

        let invalid = try XCTUnwrap(URL(string: "tboperator://messages?filter=invalid"))
        XCTAssertFalse(store.open(invalid))
        XCTAssertEqual(store.pendingTarget, .dashboard)
        XCTAssertEqual(store.routeGeneration, generation)

        store.route(to: .messages(.list(filter: .review)))
        XCTAssertEqual(store.pendingTarget, .messages(.list(filter: .review)))
        XCTAssertEqual(store.consumePendingTarget(), .messages(.list(filter: .review)))
        XCTAssertNil(store.pendingTarget)
    }

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
