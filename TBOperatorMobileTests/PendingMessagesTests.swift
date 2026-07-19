//
//  PendingMessagesTests.swift
//
//  Covers the awaiting-moderation badge count: the model's fallback logic,
//  forward-compatible decoding, and the PendingMessagesStore refresh path.
//

import XCTest
@testable import TBOperatorMobile

@MainActor
final class PendingMessagesTests: XCTestCase {

    // MARK: - badgeCount fallback

    func testBadgeCountPrefersAwaitingModeration() {
        let messages = StatsSummary.Messages(
            pending: 3,
            awaitingModeration: 5,
            receivedToday: 9,
            latestId: nil
        )
        XCTAssertEqual(messages.badgeCount, 5)
    }

    func testBadgeCountFallsBackToPendingWhenAwaitingIsNil() {
        let messages = StatsSummary.Messages(
            pending: 4,
            awaitingModeration: nil,
            receivedToday: 9,
            latestId: nil
        )
        XCTAssertEqual(messages.badgeCount, 4)
    }

    // MARK: - Forward-compatible decoding

    func testDecodesWithoutAwaitingModerationField() throws {
        let json = Data(#"{"pending":3,"receivedToday":18,"latestId":null}"#.utf8)
        let messages = try JSONDecoder().decode(StatsSummary.Messages.self, from: json)
        XCTAssertNil(messages.awaitingModeration)
        XCTAssertEqual(messages.badgeCount, 3)
    }

    func testDecodesWithAwaitingModerationField() throws {
        let json = Data(#"{"pending":3,"awaitingModeration":7,"receivedToday":18,"latestId":null}"#.utf8)
        let messages = try JSONDecoder().decode(StatsSummary.Messages.self, from: json)
        XCTAssertEqual(messages.awaitingModeration, 7)
        XCTAssertEqual(messages.badgeCount, 7)
    }

    // MARK: - Store refresh

    func testRefreshUpdatesPendingCountFromStats() async {
        let demoClient = OperatorClient(config: .shared, auth: .shared, demoMode: true)
        let store = PendingMessagesStore.shared
        await store.refresh(using: demoClient)
        // DemoData.statsSummary advertises awaitingModeration == 4.
        XCTAssertEqual(store.pendingCount, DemoData.statsSummary.messages.badgeCount)
    }

    func testStopPollingClearsCount() async {
        let demoClient = OperatorClient(config: .shared, auth: .shared, demoMode: true)
        let store = PendingMessagesStore.shared
        await store.refresh(using: demoClient)
        XCTAssertGreaterThan(store.pendingCount, 0)
        store.stopPolling()
        // stopPolling clears the badge asynchronously.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.pendingCount, 0)
    }

    // MARK: - Human moderation decision

    func testDecisionRequestEncodesRawValue() throws {
        let body = MessageDecisionRequest(decision: .approve, notes: "looks good")
        let json = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual(object?["decision"] as? String, "approve")
        XCTAssertEqual(object?["notes"] as? String, "looks good")
    }

    func testDecisionRequestTrimsAndDropsEmptyNotes() {
        XCTAssertNil(MessageDecisionRequest(decision: .reject, notes: "   ").notes)
        XCTAssertNil(MessageDecisionRequest(decision: .reject, notes: nil).notes)
        XCTAssertEqual(MessageDecisionRequest(decision: .reject, notes: "  hi ").notes, "hi")
    }

    func testApplyingDecisionSetsStatus() {
        let base = DemoData.message(id: "msg-1")
        XCTAssertEqual(base.applyingDecision(.approve, notes: nil).status, .approved)
        let rejected = base.applyingDecision(.reject, notes: "no")
        XCTAssertEqual(rejected.status, .rejected)
        XCTAssertEqual(rejected.notes, "no")
    }

    func testDemoDecideMessageReturnsDecidedStatus() async throws {
        let client = OperatorClient(config: .shared, auth: .shared, demoMode: true)
        let approved = try await client.decideMessage(id: "demo-message-3", decision: .approve)
        XCTAssertEqual(approved.status, .approved)
        let rejected = try await client.decideMessage(id: "demo-message-3", decision: .reject, notes: "spam")
        XCTAssertEqual(rejected.status, .rejected)
    }

    func testDemoDecisionPersistsForFetchMessage() async throws {
        let client = OperatorClient(config: .shared, auth: .shared, demoMode: true)
        let decided = try await client.decideMessage(id: "demo-message-3", decision: .approve)
        let fetched = try await client.fetchMessage(id: decided.id)
        XCTAssertEqual(fetched.status, .approved)
    }

    func testDemoDecisionPersistsForMessageListFilters() async throws {
        let client = OperatorClient(config: .shared, auth: .shared, demoMode: true)
        _ = try await client.decideMessage(id: "demo-message-3", decision: .reject)
        let pending = try await client.fetchMessages(status: .pending)
        let rejected = try await client.fetchMessages(status: .rejected)
        XCTAssertFalse(pending.items.contains { $0.id == "demo-message-3" })
        XCTAssertTrue(rejected.items.contains { $0.id == "demo-message-3" })
    }
}
