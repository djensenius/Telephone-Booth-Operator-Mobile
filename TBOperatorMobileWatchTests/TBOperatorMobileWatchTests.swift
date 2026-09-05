//
//  TBOperatorMobileWatchTests.swift
//

import XCTest
@testable import TBOperatorMobileWatch

@MainActor
final class TBOperatorMobileWatchTests: XCTestCase {
    private enum Failure: Error { case offline }

    func testInitialListDoesNotClaimEmptyOrClearNotifications() {
        let model = WatchMessageListModel()
        XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.notificationScope)
    }

    func testSuccessfulEmptyListIsDistinctFromInitialLoading() async {
        let model = WatchMessageListModel()
        await model.refresh(failureMessage: "Failed") { [] }
        XCTAssertTrue(model.hasLoaded)
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.notificationScope, .messages(ids: []))
    }

    func testQueueMergesDeduplicatesAndPrefersPendingSnapshot() async {
        let model = WatchMessageListModel()
        await model.refreshReview { status in
            MessageList(items: status == .pending
                        ? [Self.message("same", status: .pending), Self.message("new", time: 30)]
                        : [Self.message("same", status: .received), Self.message("old", time: 5)])
        }
        XCTAssertEqual(model.messages.map(\.id), ["new", "same", "old"])
        XCTAssertEqual(model.messages[1].status, .pending)
        XCTAssertEqual(model.notificationScope, .messages(ids: ["new", "same", "old"]))
    }

    func testQueueSortingUsesReceivedTimeAndStableIDTieBreak() {
        let values = WatchMessageListModel.reviewMessages(
            pending: [Self.message("a"), Self.message("b"), Self.message("new", time: 1, receivedAt: 50)],
            received: [Self.message("decided", status: .approved)]
        )
        XCTAssertEqual(values.map(\.id), ["new", "b", "a"])
    }

    func testEitherQueueRequestFailurePreservesEntirePreviousSnapshot() async {
        for failedStatus in [MessageStatus.pending, .received] {
            let model = WatchMessageListModel()
            let cached = Self.message("cached")
            await model.refresh(failureMessage: "Failed") { [cached] }
            await model.refreshReview { status in
                if status == failedStatus { throw Failure.offline }
                return MessageList(items: [Self.message("partial", status: status)])
            }
            XCTAssertEqual(model.messages, [cached])
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(model.notificationScope, .messages(ids: ["cached"]))
            XCTAssertFalse(model.isRefreshing)
        }
    }

    func testFirstQueueFailureDoesNotLookLikeEmptySuccess() async {
        let model = WatchMessageListModel()
        await model.refreshReview { _ in throw Failure.offline }
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.notificationScope)
    }

    func testRetryClearsErrorAndReplacesNotificationScope() async {
        let model = WatchMessageListModel()
        await model.refresh(failureMessage: "Offline") { throw Failure.offline }
        await model.refresh(failureMessage: "Offline") { [Self.message("loaded")] }
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.messages.map(\.id), ["loaded"])
        XCTAssertEqual(model.notificationScope, .messages(ids: ["loaded"]))
    }

    func testCancelledListRefreshDoesNotCreateFailureOrEmptySnapshot() async {
        let model = WatchMessageListModel()
        await model.refresh(failureMessage: "Failed") { throw CancellationError() }
        XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.notificationScope)
    }

    func testListRejectsOverlappingRefresh() async {
        let model = WatchMessageListModel()
        await model.refresh(failureMessage: "Failed") {
            XCTAssertTrue(model.isRefreshing)
            await model.refresh(failureMessage: "Failed") {
                XCTFail("Overlapping request must not run")
                return []
            }
            return [Self.message("first")]
        }
        XCTAssertEqual(model.messages.map(\.id), ["first"])
    }

    func testSuccessfulDecisionRemovesQueueRowEvenWhenFollowingRefreshFails() async {
        let queue = WatchMessageListModel()
        let latest = WatchMessageListModel()
        let pending = Self.message("pending")
        let rejected = pending.applyingDecision(.reject, notes: nil)
        await queue.refresh(failureMessage: "Failed") { [pending] }
        await latest.refresh(failureMessage: "Failed") { [pending] }
        queue.applyDecision(rejected, filter: .review)
        latest.applyDecision(rejected, filter: .all)
        await queue.refresh(failureMessage: "Failed") { throw Failure.offline }
        XCTAssertTrue(queue.messages.isEmpty)
        XCTAssertEqual(latest.messages, [rejected])
        XCTAssertNotNil(queue.errorMessage)
    }

    func testRefreshStartedBeforeDecisionCannotRestoreOldQueueRow() async {
        let model = WatchMessageListModel()
        let pending = Self.message("pending")
        await model.refresh(failureMessage: "Failed") { [pending] }
        await model.refresh(failureMessage: "Failed") {
            model.applyDecision(pending.applyingDecision(.approve, notes: nil), filter: .review)
            return [pending]
        }
        XCTAssertTrue(model.messages.isEmpty)
    }

    func testFetchedNotificationScopeLeavesUnfetchedAndAggregateAlertsAlone() async {
        let model = WatchMessageListModel()
        await model.refresh(failureMessage: "Failed") { [Self.message("seen")] }
        guard let scope = model.notificationScope else {
            return XCTFail("Successful load needs a scoped notification descriptor")
        }
        XCTAssertTrue(NotificationManager.shouldClearDeliveredNotification(
            categoryIdentifier: "BOOTH_MESSAGE", userInfo: ["messageId": "seen"], in: scope
        ))
        XCTAssertFalse(NotificationManager.shouldClearDeliveredNotification(
            categoryIdentifier: "BOOTH_MESSAGE", userInfo: ["messageId": "unfetched"], in: scope
        ))
        XCTAssertFalse(NotificationManager.shouldClearDeliveredNotification(
            categoryIdentifier: "BOOTH_MESSAGE", userInfo: ["awaitingModeration": 100], in: scope
        ))
    }

    func testDecisionAvailabilityMatchesPhoneStatusPolicy() async {
        let cases: [(MessageStatus, Set<MessageDecision>)] = [
            (.uploading, []), (.received, []),
            (.pending, [.approve, .reject]), (.approved, [.reject]),
            (.rejected, [.approve]), (.unknown("future"), [])
        ]
        for (status, allowed) in cases {
            let model = WatchMessageDetailModel()
            XCTAssertFalse(model.canDecide(.approve))
            await model.load { Self.message("message", status: status) }
            XCTAssertEqual(model.canDecide(.approve), allowed.contains(.approve), status.rawValue)
            XCTAssertEqual(model.canDecide(.reject), allowed.contains(.reject), status.rawValue)
        }
    }

    func testDecisionReturnsServerResponseAndPreventsDuplicateSubmission() async {
        let model = WatchMessageDetailModel()
        let pending = Self.message("message")
        let approved = pending.applyingDecision(.approve, notes: "Server saved")
        await model.load { pending }
        let result = await model.decide(.approve) {
            XCTAssertTrue(model.isDeciding)
            XCTAssertFalse(model.canDecide(.approve))
            XCTAssertFalse(model.canDecide(.reject))
            let duplicate = await model.decide(.approve) {
                XCTFail("Duplicate submission must not run")
                return approved
            }
            XCTAssertNil(duplicate)
            await model.load {
                XCTFail("A load cannot overwrite an in-flight decision")
                return pending
            }
            return approved
        }
        XCTAssertEqual(result, approved)
        XCTAssertEqual(model.message, approved)
        XCTAssertFalse(model.isDeciding)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.notificationScope, .messages(ids: ["message"]))
    }

    func testFailedDecisionRequiresReloadBeforeRetryAndNeverUpdatesOptimistically() async {
        let model = WatchMessageDetailModel()
        let pending = Self.message("message")
        await model.load { pending }
        let result = await model.decide(.reject) { throw Failure.offline }
        XCTAssertNil(result)
        XCTAssertEqual(model.message, pending)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isDeciding)
        XCTAssertFalse(model.canDecide(.reject))
        await model.load { pending }
        XCTAssertTrue(model.canDecide(.reject))
        XCTAssertNil(model.errorMessage)
    }

    func testFailedDetailRefreshPreservesTranscriptButDisablesDecisions() async {
        let model = WatchMessageDetailModel()
        let pending = Self.message("message")
        await model.load { pending }
        await model.load { throw Failure.offline }
        XCTAssertEqual(model.message, pending)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.canDecide(.approve))
        let result = await model.decide(.approve) {
            XCTFail("Stale detail must reload before submitting")
            return pending
        }
        XCTAssertNil(result)
    }

    func testDetailCancellationDoesNotShowSpuriousFailure() async {
        let model = WatchMessageDetailModel()
        await model.load { throw CancellationError() }
        XCTAssertNil(model.message)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.notificationScope)
        XCTAssertFalse(model.isLoading)
    }

    func testDemoClientDecisionPersistsThroughQueueRefresh() async throws {
        let client = OperatorClient(config: .shared, auth: .shared, demoMode: true)
        let list = try await client.fetchMessages(status: .pending)
        let pending = try XCTUnwrap(list.items.first)
        let detail = WatchMessageDetailModel()
        await detail.load { try await client.fetchMessage(id: pending.id) }
        let result = await detail.decide(.reject) {
            try await client.decideMessage(id: pending.id, decision: .reject)
        }
        XCTAssertEqual(result?.status, .rejected)
        let queue = WatchMessageListModel()
        await queue.refreshReview { try await client.fetchMessages(status: $0, limit: 25) }
        XCTAssertTrue(queue.hasLoaded)
        XCTAssertFalse(queue.messages.contains { $0.id == pending.id })
        let reloaded = try await client.fetchMessage(id: pending.id)
        XCTAssertEqual(reloaded.status, .rejected)
    }

    func testSupportedNavigationRoutesUseOneMessagePath() {
        let detail = WatchRoute(target: .messages(.detail(id: "message")))
        XCTAssertEqual(detail.page, .moderation)
        XCTAssertEqual(detail.path, [.message("message")])
        XCTAssertNil(detail.notice)
        XCTAssertEqual(WatchRoute(target: .dashboard).page, .status)
        XCTAssertEqual(WatchRoute(target: .stats).page, .stats)
        XCTAssertEqual(WatchRoute(target: .messages(.list(filter: .review))).page, .moderation)
    }

    func testUnsupportedRoutesExplainPhoneRequirementInsteadOfSilentlyDisappearing() {
        for target: AppNavigationTarget in [.sessions, .session(id: "session"), .thermals, .system] {
            let route = WatchRoute(target: target)
            XCTAssertEqual(route.page, .status)
            XCTAssertTrue(route.path.isEmpty)
            XCTAssertNotNil(route.notice)
        }
        for filter in [MessageListFilter.all, .approved, .rejected] {
            let route = WatchRoute(target: .messages(.list(filter: filter)))
            XCTAssertEqual(route.page, .latest)
            XCTAssertNotNil(route.notice)
        }
    }

    func testRepeatedNotificationRoutesAreConsumedAndCanReopenSameDetail() {
        let store = AppNavigationStore()
        let target = AppNavigationTarget.messages(.detail(id: "same"))
        store.route(to: target)
        let firstGeneration = store.routeGeneration
        XCTAssertEqual(store.consumePendingTarget(), target)
        XCTAssertNil(store.pendingTarget)
        store.route(to: target)
        XCTAssertNotEqual(store.routeGeneration, firstGeneration)
        XCTAssertEqual(store.consumePendingTarget(), target)
    }

    func testUnavailableAndUnknownBoothStatesDoNotClaimStandby() {
        XCTAssertEqual(BoothState.idle.watchActivityDescription, "Standby")
        XCTAssertEqual(BoothState.dialTone.watchActivityDescription, "Ready to dial")
        XCTAssertEqual(BoothState.recording.watchActivityDescription, "Call in progress")
        XCTAssertNotEqual(BoothState.error.watchActivityDescription, "Standby")
        XCTAssertNotEqual(BoothState.callUnavailable.watchActivityDescription, "Standby")
        XCTAssertNotEqual(BoothState.unknown("future").watchActivityDescription, "Standby")
    }

    func testExpiredBrokeredSessionDefersRestoreWithoutDiscardingCredentials() async {
        let auth = AuthManager(keychainStore: WatchTestKeychain())
        auth.storeTokens(OIDCTokens(
            accessToken: "expired-watch", refreshToken: nil,
            idToken: nil, expiresIn: -10, tokenType: "Bearer"
        ))
        auth.resetStateForTesting()
        auth.watchTokenProvider = { force in
            XCTAssertFalse(force)
            return false
        }

        await auth.restoreSession(scheduleRetry: false)

        XCTAssertEqual(auth.authState, .unknown)
        XCTAssertTrue(auth.sessionRestoreFailed)
        XCTAssertEqual(auth.getAccessToken(), "expired-watch")
    }

    func testStillValidWatchTokenSurvivesPhoneRenewalFailure() async {
        let auth = AuthManager(keychainStore: WatchTestKeychain())
        XCTAssertTrue(auth.applyBrokeredAccessToken(
            accessToken: "watch-cache", expiry: Date().addingTimeInterval(30).timeIntervalSince1970
        ))
        auth.watchTokenProvider = { force in
            XCTAssertFalse(force)
            return false
        }

        let usable = await auth.ensureValidToken()

        XCTAssertTrue(usable)
        XCTAssertEqual(auth.authState, .signedIn)
        XCTAssertEqual(auth.getAccessToken(), "watch-cache")
    }

    func testWatchUnauthorizedRefreshForcesPhoneRenewalWithoutRefreshToken() async {
        let auth = AuthManager(keychainStore: WatchTestKeychain())
        var forces: [Bool] = []
        auth.watchTokenProvider = { force in
            forces.append(force)
            return auth.applyBrokeredAccessToken(
                accessToken: "renewed-watch", expiry: Date().addingTimeInterval(300).timeIntervalSince1970
            )
        }

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertTrue(refreshed)
        XCTAssertEqual(forces, [true])
        XCTAssertEqual(auth.getAccessToken(), "renewed-watch")
        XCTAssertNil(auth.getKeychainItem(account: "oidc_refresh_token"))
        auth.watchTokenProvider = { _ in false }
    }

    func testWatchSignOutPausesAutomaticHandoffUntilExplicitConnection() async {
        let defaults = UserDefaults.standard
        let key = WatchAuthSync.autoSignInPausedKey
        let previous = defaults.object(forKey: key)
        defer { defaults.set(previous, forKey: key) }
        let auth = AuthManager(keychainStore: WatchTestKeychain())
        var requests = 0
        let sync = WatchAuthSync(auth: auth) { _ in
            requests += 1
            let config = AppConfig.shared
            return .token(
                accessToken: "connected-watch",
                expiry: Date().addingTimeInterval(300).timeIntervalSince1970,
                issuer: config.oidcIssuerBase, clientID: config.oidcClientID,
                apiBase: config.apiBaseURL.absoluteString
            )
        }
        auth.signOut()

        await sync.connectFromLogin(automatically: true)
        XCTAssertTrue(defaults.bool(forKey: key))
        XCTAssertEqual(requests, 0)
        let backgroundRequest = await sync.ensureBrokeredToken()
        XCTAssertFalse(backgroundRequest)

        await sync.connectFromLogin(automatically: false)
        XCTAssertFalse(defaults.bool(forKey: key))
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(auth.authState, .signedIn)
    }

    private static func message(
        _ id: String,
        status: MessageStatus = .pending,
        time: TimeInterval = 10,
        receivedAt: TimeInterval? = nil
    ) -> Message {
        Message(
            id: id, status: status, questionId: nil, notes: nil,
            createdAt: Date(timeIntervalSince1970: time),
            receivedAt: receivedAt.map { Date(timeIntervalSince1970: $0) },
            audio: DemoData.messages[0].audio,
            latestTranscription: nil, latestModeration: nil
        )
    }

    @MainActor
    private final class WatchTestKeychain: KeychainStoring {
        private var values: [String: String] = [:]
        func migrateAccessibility(service: String, accounts: [String], to accessibility: KeychainAccessibility) {}
        func set(service: String, account: String, value: String, accessibility: KeychainAccessibility) -> Bool {
            values[account] = value
            return true
        }
        func get(service: String, account: String) -> String? { values[account] }
        func delete(service: String, account: String) { values[account] = nil }
    }
}
