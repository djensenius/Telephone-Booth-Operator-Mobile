// swiftlint:disable file_length
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

    func testDemoDeleteRemovesMessageInsteadOfRejectingIt() async throws {
        let client = OperatorClient(config: .shared, auth: .shared, demoMode: true)
        try await client.deleteMessage(id: "demo-message-3")
        let all = try await client.fetchMessages()
        XCTAssertFalse(all.items.contains { $0.id == "demo-message-3" })
        do {
            _ = try await client.fetchMessage(id: "demo-message-3")
            XCTFail("Deleted messages must not be fetchable")
        } catch let OperatorError.httpError(status, _) {
            XCTAssertEqual(status, 404)
        }
    }

    func testMessagePageDecodesMissingAndOpaqueCursor() throws {
        let missing = try OperatorJSON.decoder.decode(
            MessagePage.self,
            from: Data(#"{"items":[]}"#.utf8)
        )
        let opaque = try OperatorJSON.decoder.decode(
            MessagePage.self,
            from: Data(#"{"items":[],"nextCursor":"opaque.cursor_2"}"#.utf8)
        )

        XCTAssertNil(missing.nextCursor)
        XCTAssertEqual(opaque.nextCursor, "opaque.cursor_2")
    }

    func testDemoQuestionMessagesFilterAndPageAfterCursorRowDeletion() async throws {
        let client = OperatorClient(config: .shared, auth: .shared, demoMode: true)
        let questionId = try XCTUnwrap(DemoData.questions.first?.id)
        let first = try await client.fetchQuestionMessages(questionId: questionId, limit: 2)
        let cursor = try XCTUnwrap(first.nextCursor)

        XCTAssertEqual(first.items.map(\.id), ["demo-message-3", "demo-message-2"])
        try await client.deleteMessage(id: "demo-message-2")

        let second = try await client.fetchQuestionMessages(
            questionId: questionId,
            cursor: cursor,
            limit: 2
        )
        let unrelated = try await client.fetchQuestionMessages(
            questionId: "demo-question-2"
        )

        XCTAssertEqual(second.items.map(\.id), ["demo-message-1"])
        XCTAssertNil(second.nextCursor)
        XCTAssertTrue(unrelated.items.isEmpty)
    }

    func testQuestionModeIncludesOnlyMatchingAnswers() throws {
        let matching = DemoData.message(id: "demo-message-1")
        let unrelated = Message(
            id: "unrelated",
            status: matching.status,
            installationId: matching.installationId,
            questionId: "another-question",
            notes: matching.notes,
            createdAt: matching.createdAt,
            receivedAt: matching.receivedAt,
            audio: matching.audio,
            latestTranscription: matching.latestTranscription,
            latestModeration: matching.latestModeration
        )
        let mode = MessageListMode.question(
            id: try XCTUnwrap(matching.questionId),
            prompt: "Prompt"
        )

        XCTAssertTrue(mode.includes(matching, filter: .all))
        XCTAssertFalse(mode.includes(unrelated, filter: .all))
        XCTAssertFalse(mode.shouldDismissDetail(afterDecisionTo: .approved, filter: .all))
    }

    func testQuestionModeScopesNotificationsToLoadedAnswerIds() throws {
        let messages = [
            DemoData.message(id: "demo-message-1"),
            DemoData.message(id: "demo-message-2")
        ]
        let questionId = try XCTUnwrap(messages.first?.questionId)
        let scope = MessageListMode.question(
            id: questionId,
            prompt: "Prompt"
        ).notificationScope(for: messages, filter: .all)

        XCTAssertEqual(scope, .messages(ids: Set(messages.map(\.id))))
    }

    func testQuestionModeOnlyAllowsActionsForCurrentInstallation() {
        let message = DemoData.message(id: "demo-message-1")
        let activeInstallationId = DemoData.installations.first(where: \.isActive)?.id
        let mode = MessageListMode.question(
            id: message.questionId ?? "question",
            prompt: "Prompt"
        )

        XCTAssertEqual(message.installationId, activeInstallationId)
        XCTAssertEqual(
            mode.actionAccess(
                for: message,
                installationState: .available(currentInstallationId: activeInstallationId)
            ),
            .writable
        )
        XCTAssertEqual(
            mode.actionAccess(
                for: message,
                installationState: .available(currentInstallationId: "archived-installation")
            ),
            .readOnlyArchived
        )
        XCTAssertEqual(
            mode.actionAccess(for: message, installationState: .loading),
            .checking
        )
        XCTAssertEqual(
            mode.actionAccess(for: message, installationState: .unavailable),
            .readOnlyUnavailable
        )
        XCTAssertEqual(
            MessageListMode.queue.actionAccess(
                for: message,
                installationState: .unavailable
            ),
            .writable
        )
        XCTAssertEqual(
            MessageActionAccess.installationScoped(
                messageInstallationId: nil,
                currentInstallationId: nil
            ),
            .readOnlyArchived
        )
    }

    func testQuestionPagesDeduplicateAndKeepNewestServerOrder() {
        let older = DemoData.message(id: "demo-message-1")
        let newer = Message(
            id: "answer-2",
            status: .pending,
            installationId: older.installationId,
            questionId: older.questionId,
            notes: nil,
            createdAt: older.createdAt.addingTimeInterval(60),
            receivedAt: older.receivedAt?.addingTimeInterval(60),
            audio: older.audio,
            latestTranscription: older.latestTranscription,
            latestModeration: older.latestModeration
        )
        let updatedOlder = older.applyingDecision(.approve, notes: nil)

        let merged = [older, newer, updatedOlder].deduplicatedNewestFirst()

        XCTAssertEqual(merged.map(\.id), [newer.id, older.id])
        XCTAssertEqual(merged.last?.status, .approved)
    }

    func testLiveMessageUpdateInsertsAndSortsMissingMessage() {
        let older = DemoData.message(id: "older")
        var messages = [older]
        let newer = Message(
            id: "newer",
            status: .pending,
            installationId: older.installationId,
            questionId: older.questionId,
            notes: nil,
            createdAt: older.createdAt.addingTimeInterval(60),
            receivedAt: older.receivedAt?.addingTimeInterval(60),
            audio: older.audio,
            latestTranscription: older.latestTranscription,
            latestModeration: older.latestModeration
        )

        messages.applyLiveUpdate(newer, isIncluded: true)

        XCTAssertEqual(messages.map(\.id), ["newer", older.id])
    }

    func testLiveMessageUpdateRemovesMessageThatLeavesFilter() {
        let message = DemoData.message(id: "message")
        var messages = [message]

        messages.applyLiveUpdate(message, isIncluded: false)

        XCTAssertTrue(messages.isEmpty)
    }

    func testQuestionModeIgnoresUnknownSocketUpdatesBeyondLoadedWindow() throws {
        let newest = DemoData.message(id: "demo-message-3")
        let oldest = DemoData.message(id: "demo-message-2")
        let questionId = try XCTUnwrap(newest.questionId)
        let olderUnloaded = Message(
            id: "older-unloaded",
            status: .approved,
            installationId: oldest.installationId,
            questionId: questionId,
            notes: nil,
            createdAt: oldest.createdAt.addingTimeInterval(-60),
            receivedAt: oldest.receivedAt?.addingTimeInterval(-60),
            audio: oldest.audio,
            latestTranscription: oldest.latestTranscription,
            latestModeration: oldest.latestModeration
        )
        let mode = MessageListMode.question(id: questionId, prompt: "Prompt")

        XCTAssertEqual(
            mode.liveUpdateDisposition(
                for: olderUnloaded,
                loadedMessages: [newest, oldest],
                hasMore: true,
                filter: .all
            ),
            .ignore
        )
        XCTAssertEqual(
            mode.liveUpdateDisposition(
                for: olderUnloaded,
                loadedMessages: [newest, oldest],
                hasMore: false,
                filter: .all
            ),
            .upsert
        )
    }

    func testRefreshMutationsOverrideStaleSnapshot() {
        let original = DemoData.message(id: "demo-message-1")
        let removed = DemoData.message(id: "demo-message-2")
        let approved = original.applyingDecision(.approve, notes: nil)

        let reconciled = [original, removed].applying([
            .upsert(approved),
            .remove(removed.id)
        ])

        XCTAssertEqual(reconciled.map(\.id), [approved.id])
        XCTAssertEqual(reconciled.first?.status, .approved)
    }

    func testRefreshOnlyAppliesMutationsNewerThanRequest() {
        let original = DemoData.message(id: "demo-message-1")
        let approved = original.applyingDecision(.approve, notes: nil)
        let rejected = original.applyingDecision(.reject, notes: nil)
        let mutations = [
            MessageListMutationRecord(sequence: 1, mutation: .remove(original.id)),
            MessageListMutationRecord(sequence: 2, mutation: .upsert(rejected))
        ]

        let reconciled = [approved].applying(mutations.mutations(after: 1))

        XCTAssertEqual(reconciled.map(\.id), [original.id])
        XCTAssertEqual(reconciled.first?.status, .rejected)
        XCTAssertTrue(mutations.mutations(after: 2).isEmpty)
    }
}

final class StatsOverviewCompatibilityTests: XCTestCase {
    func testInstallationSummaryFallsBackToLegacyCalls() throws {
        let summary = try OperatorJSON.decoder.decode(
            InstallationSummary.self,
            from: Data(#"""
            {
              "calls": 12,
              "messages": 6,
              "allRecordings": 8,
              "questions": 2,
              "events": 90,
              "recordedMs": 120000,
              "firstActivityAt": "2026-08-14T12:00:00Z",
              "lastActivityAt": "2026-08-15T12:00:00Z"
            }
            """#.utf8)
        )

        XCTAssertEqual(summary.interactionTotal, 12)
        XCTAssertEqual(summary.messagesLeftCount, 8)
        XCTAssertNil(summary.interactionBreakdown)
    }

    func testInstallationSummaryDecodesAdditiveInteractionBreakdown() throws {
        let summary = try OperatorJSON.decoder.decode(
            InstallationSummary.self,
            from: Data(#"""
            {
              "calls": 12,
              "interactions": 15,
              "interactionBreakdown": {
                "noSelection": 4,
                "wrongNumberAttempts": 7,
                "messagesLeft": 9,
                "messagePlaybackStarts": 5,
                "instructionPlaybackStarts": 2
              },
              "messages": 6,
              "questions": 2,
              "events": 90,
              "recordedMs": 120000,
              "firstActivityAt": "2026-08-14T12:00:00Z",
              "lastActivityAt": "2026-08-15T12:00:00Z"
            }
            """#.utf8)
        )

        XCTAssertEqual(summary.interactionTotal, 15)
        XCTAssertEqual(summary.messagesLeftCount, 9)
        XCTAssertEqual(summary.interactionBreakdown?.wrongNumberAttempts, Optional(7))
    }

    @MainActor
    func testFetchStatsOverviewRecoversDigitsAndKeepsOverviewWhenRecoveryFails() async throws {
        let appConfig = AppConfig.shared
        let previousDemoMode = appConfig.isDemoMode
        appConfig.isDemoMode = false
        defer { appConfig.isDemoMode = previousDemoMode }

        let auth = AuthManager(keychainStore: TestKeychainStore())
        let stored = auth.storeTokens(
            OIDCTokens(
                accessToken: "stats-access-\(UUID().uuidString)",
                refreshToken: "stats-refresh-\(UUID().uuidString)",
                idToken: nil,
                expiresIn: 3_600,
                tokenType: "Bearer"
            )
        )
        XCTAssertTrue(stored)
        defer { auth.signOut() }
        StatsDigitRecoveryURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatsDigitRecoveryURLProtocol.self]
        let client = OperatorClient(
            config: appConfig,
            auth: auth,
            session: URLSession(configuration: configuration)
        )
        let overview = try await client.fetchStatsOverview(
            selection: .window(.last7d),
            installationScope: .installation("installation-1")
        )

        XCTAssertEqual(overview.pickupsHangups.digitsDialed["0"], 1)
        XCTAssertEqual(overview.pickupsHangups.digitsDialed["1"], 2)
        XCTAssertEqual(overview.pickupsHangups.digitsDialed["5"], 2)
        XCTAssertEqual(overview.pickupsHangups.digitsDialed["9"], 0)

        let requests = StatsDigitRecoveryURLProtocol.capturedURLs()
        XCTAssertEqual(requests.filter { $0.path == "/v1/stats/overview" }.count, 1)
        let eventRequests = requests.filter { $0.path == "/v1/events" }
        XCTAssertEqual(eventRequests.count, 2)
        let firstEventRequest = try XCTUnwrap(eventRequests.first)
        let firstQuery = try XCTUnwrap(URLComponents(
            url: firstEventRequest,
            resolvingAgainstBaseURL: false
        )?.queryItems)
        XCTAssertTrue(firstQuery.contains(URLQueryItem(name: "type", value: "digit_dialed")))
        XCTAssertTrue(firstQuery.contains(URLQueryItem(name: "installationId", value: "installation-1")))
        XCTAssertNotNil(firstQuery.first(where: { $0.name == "since" })?.value)
        XCTAssertNotNil(firstQuery.first(where: { $0.name == "until" })?.value)
        let lastEventRequest = try XCTUnwrap(eventRequests.last)
        let secondQuery = try XCTUnwrap(URLComponents(
            url: lastEventRequest,
            resolvingAgainstBaseURL: false
        )?.queryItems)
        XCTAssertTrue(secondQuery.contains(URLQueryItem(name: "cursor", value: "next-page")))

        let cached = try await client.fetchStatsOverview(
            selection: .window(.last7d),
            installationScope: .installation("installation-1")
        )
        XCTAssertEqual(cached.pickupsHangups.digitsDialed["1"], 2)
        XCTAssertEqual(StatsDigitRecoveryURLProtocol.capturedURLs().filter { $0.path == "/v1/events" }.count, 2)

        StatsDigitRecoveryURLProtocol.reset(failEventRequests: true)
        let fallback = try await client.fetchStatsOverview(
            selection: .window(.last7d),
            installationScope: .installation("installation-2")
        )
        XCTAssertEqual(fallback.calls.total, 2)
        XCTAssertEqual(fallback.pickupsHangups.digitsDialed.values.reduce(0, +), 0)
        XCTAssertEqual(StatsDigitRecoveryURLProtocol.capturedURLs().filter { $0.path == "/v1/events" }.count, 1)

        StatsDigitRecoveryURLProtocol.reset(reportedDigitCount: 8)
        let authoritative = try await client.fetchStatsOverview(
            selection: .window(.last7d),
            installationScope: .installation("installation-3")
        )
        XCTAssertEqual(authoritative.pickupsHangups.digitsDialed["1"], 8)
        XCTAssertEqual(StatsDigitRecoveryURLProtocol.capturedURLs().filter { $0.path == "/v1/events" }.count, 0)

        StatsDigitRecoveryURLProtocol.reset(zeroTotalsOverview: true)
        let actionOnly = try await client.fetchStatsOverview(
            selection: .window(.last7d),
            installationScope: .installation("installation-action-only")
        )
        XCTAssertEqual(actionOnly.calls.total, 0)
        XCTAssertEqual(actionOnly.pickupsHangups.pickups, 0)
        XCTAssertEqual(actionOnly.pickupsHangups.hangups, 0)
        XCTAssertEqual(actionOnly.pickupsHangups.digitsDialed["1"], 2)
        XCTAssertEqual(StatsDigitRecoveryURLProtocol.capturedURLs().filter { $0.path == "/v1/events" }.count, 2)

        StatsDigitRecoveryURLProtocol.reset(includeActionsPayload: true)
        let additive = try await client.fetchStatsOverview(
            selection: .window(.last7d),
            installationScope: .installation("installation-4")
        )
        XCTAssertEqual(additive.actionMetrics.leaveMessageSelections, 5)
        XCTAssertEqual(additive.actionMetrics.messagePlaybackStarts, Optional(3))
        XCTAssertEqual(additive.pickupsHangups.digitsDialed.values.reduce(0, +), 0)
        XCTAssertEqual(StatsDigitRecoveryURLProtocol.capturedURLs().filter { $0.path == "/v1/events" }.count, 0)
    }
}

private final class StatsDigitRecoveryURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var requests: [URL] = []
    nonisolated(unsafe) private static var shouldFailEventRequests = false
    nonisolated(unsafe) private static var reportedDigitCount = 0
    nonisolated(unsafe) private static var zeroTotalsOverview = false
    nonisolated(unsafe) private static var includeActionsPayload = false
    private static let lock = NSLock()

    static func reset(
        failEventRequests: Bool = false,
        reportedDigitCount: Int = 0,
        zeroTotalsOverview: Bool = false,
        includeActionsPayload: Bool = false
    ) {
        lock.lock()
        requests = []
        shouldFailEventRequests = failEventRequests
        self.reportedDigitCount = reportedDigitCount
        self.zeroTotalsOverview = zeroTotalsOverview
        self.includeActionsPayload = includeActionsPayload
        lock.unlock()
    }

    static func capturedURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        Self.requests.append(url)
        Self.lock.unlock()

        let body: String
        let statusCode: Int
        switch url.path {
        case "/v1/stats/overview":
            body = Self.overviewResponseBody()
            statusCode = 200
        case "/v1/events":
            if Self.eventRequestsShouldFail() {
                body = #"{"error":"temporarily_unavailable"}"#
                statusCode = 503
            } else {
                let cursor = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "cursor" })?
                    .value
                body = cursor == nil
                    ? Self.firstEventPage
                    : #"{"items":[{"payload":{"digit":0}},{"payload":{"digit":5}}],"nextCursor":null}"#
                statusCode = 200
            }
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func eventRequestsShouldFail() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return shouldFailEventRequests
    }

    private static func overviewResponseBody() -> String {
        lock.lock()
        defer { lock.unlock() }
        if includeActionsPayload {
            return additiveOverviewResponse
        }
        if zeroTotalsOverview { return zeroTotalsOverviewResponse }
        return overviewResponse.replacingOccurrences(
            of: #""1": 0"#,
            with: #""1": \#(reportedDigitCount)"#
        )
    }

    private static let firstEventPage = #"""
    { "items": [
        { "payload": { "digit": 1 } }, { "payload": { "digit": 1 } },
        { "payload": { "digit": 5 } }, {}, { "payload": null },
        { "payload": "invalid" }, { "payload": { "digit": "1" } },
        { "payload": { "digit": 12 } }
      ], "nextCursor": "next-page" }
    """#

    private static let overviewResponse = #"""
    {
      "window": "7d", "rangeStart": "2026-08-12T12:00:00Z",
      "rangeEnd": "2026-08-19T12:00:00Z", "generatedAt": "2026-08-19T12:00:00Z",
      "timezone": "UTC",
      "calls": {
        "total": 2, "completed": 1, "inProgress": 0,
        "averageDurationMs": null, "longestDurationMs": null,
        "outcomes": { "recording_completed": 1 }, "perDay": []
      },
      "messages": { "total": 0, "byStatus": {}, "averageDurationMs": null },
      "playback": { "totalPlaybacks": 0 },
      "pickupsHangups": {
        "pickups": 2, "hangups": 2,
        "digitsDialed": { "0": 0, "1": 0, "2": 0, "3": 0, "4": 0,
          "5": 0, "6": 0, "7": 0, "8": 0, "9": 0 }
      },
      "uploads": { "succeeded": 0, "failed": 0, "failureRate": null },
      "topQuestions": [], "hourly": [],
      "busiest": { "hour": null, "dayOfWeek": null },
      "lastActivityAt": null, "boothBreakdown": []
    }
    """#

    private static let zeroTotalsOverviewResponse = overviewResponse
        .replacingOccurrences(
            of: #""total": 2, "completed": 1, "inProgress": 0"#,
            with: #""total": 0, "completed": 0, "inProgress": 0"#
        )
        .replacingOccurrences(of: #""outcomes": { "recording_completed": 1 }"#, with: #""outcomes": {}"#)
        .replacingOccurrences(of: #""pickups": 2, "hangups": 2"#, with: #""pickups": 0, "hangups": 0"#)

    private static let additiveOverviewResponse = #"""
    {
      "window": "7d", "rangeStart": "2026-08-12T12:00:00Z",
      "rangeEnd": "2026-08-19T12:00:00Z", "generatedAt": "2026-08-19T12:00:00Z",
      "timezone": "UTC",
      "calls": {
        "total": 2, "completed": 1, "inProgress": 0,
        "averageDurationMs": null, "longestDurationMs": null,
        "outcomes": { "recording_completed": 1 }, "perDay": []
      },
      "interactions": {
        "total": 2, "inProgressNow": 0, "noSelection": 1, "messagesLeft": 1,
        "averageDurationMs": null, "longestDurationMs": null,
        "outcomes": { "recording_completed": 1, "hung_up_before_dial": 1 }, "perDay": []
      },
      "actions": {
        "digitsDialed": { "0": 1, "1": 5, "2": 2, "3": 0, "4": 0, "5": 0, "6": 0, "7": 0, "8": 0, "9": 0 },
        "leaveMessageSelections": 5,
        "listenMessageSelections": 2,
        "instructionSelections": 1,
        "wrongNumberAttempts": 0,
        "messagePlaybackStarts": 3,
        "instructionPlaybackStarts": 1
      },
      "messages": { "total": 0, "byStatus": {}, "averageDurationMs": null },
      "playback": { "totalPlaybacks": 4 },
      "pickupsHangups": {
        "pickups": 2, "hangups": 2,
        "digitsDialed": { "0": 0, "1": 0, "2": 0, "3": 0, "4": 0,
          "5": 0, "6": 0, "7": 0, "8": 0, "9": 0 }
      },
      "uploads": { "succeeded": 0, "failed": 0, "failureRate": null },
      "topQuestions": [], "hourly": [],
      "busiest": { "hour": null, "dayOfWeek": null },
      "lastActivityAt": null, "boothBreakdown": []
    }
    """#
}
