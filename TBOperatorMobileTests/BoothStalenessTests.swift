//
//  BoothStalenessTests.swift
//
//  Tests for shared view helpers.
//

import XCTest
import os
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

    func testOnlyExplicitInactiveSuppressesOfflineAlarms() {
        let epoch = Date(timeIntervalSince1970: 0)
        for state: InstallationState? in [nil, .active] {
            XCTAssertEqual(boothStaleness(
                lastStatusAt: epoch, now: now, installationState: state
            ).level, .offline)
        }
        let inactive = boothStaleness(
            lastStatusAt: epoch, now: now, installationState: .betweenExhibitions
        )
        XCTAssertEqual(inactive.level, .expectedDowntime)
        XCTAssertEqual(inactive.label, "Offline expected")
    }
}

final class InstallationLifecycleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testUnknownLifecycleRoundTripsWithoutImplyingDowntime() throws {
        let status = try decodeStatus("""
        {"state":"idle","updatedAt":"2026-09-15T12:00:00Z","installationState":"future_state"}
        """)
        XCTAssertEqual(status.installationState, .unknown("future_state"))
        XCTAssertFalse(status.isBetweenExhibitions)
        XCTAssertNil(status.lifecycleTitle)
        XCTAssertEqual(try OperatorJSON.decoder.decode(
            BoothStatus.self, from: OperatorJSON.encoder.encode(status)
        ), status)
    }

    func testLegacyStatusDecodesWithoutImplyingDowntime() throws {
        let status = try decodeStatus("""
        {"state":"idle","updatedAt":"2026-09-15T12:00:00Z"}
        """)
        XCTAssertNil(status.installationState)
        XCTAssertNil(status.isSynthetic)
        XCTAssertFalse(status.isBetweenExhibitions)
        XCTAssertTrue(status.hasTelemetry)
        XCTAssertNil(status.lifecycleTitle)
    }

    func testSyntheticInactiveDecodesWithoutBecomingAHeartbeat() throws {
        let status = try inactive()
        XCTAssertNil(status.id)
        XCTAssertEqual(status.updatedAt, Date(timeIntervalSince1970: 0))
        XCTAssertFalse(status.hasTelemetry)
        XCTAssertEqual(status.lifecycleTitle, "Between exhibitions")
        XCTAssertNil(status.liveActivityState)
        let roundTrip = try OperatorJSON.decoder.decode(
            BoothStatus.self, from: OperatorJSON.encoder.encode(status)
        )
        XCTAssertEqual(roundTrip, status)
        XCTAssertEqual(status.reported(at: now, repeatCount: 2).installationState, .betweenExhibitions)
    }

    @MainActor
    func testInactiveEpochReplacesNewerStatusAndPreservesHistoryAndMetrics() throws {
        let store = BoothStatusLiveStore(client: .demo)
        store.applyStats(DemoData.statsSummary)
        let count = store.stats?.interactionsToday
        let history = store.history
        store.applyRESTStatusForTesting(try inactive())
        XCTAssertEqual(store.status?.installationState, .betweenExhibitions)
        XCTAssertEqual(store.status?.isSynthetic, true)
        XCTAssertEqual(store.stats?.booth.installationState, .betweenExhibitions)
        XCTAssertEqual(store.stats?.interactionsToday, count)
        XCTAssertEqual(store.history, history)

        store.apply(.status(BoothStatus(
            state: .recording, updatedAt: now.addingTimeInterval(100),
            installationState: .active
        )))
        XCTAssertEqual(store.status?.isSynthetic, true, "Status frames cannot start installations")
        XCTAssertEqual(store.installationState, .betweenExhibitions)
        XCTAssertEqual(store.history, history)
    }

    @MainActor
    func testRESTSummaryReconcilesMissedEndAndManualRestart() throws {
        let store = BoothStatusLiveStore(client: .demo)
        store.applyRESTStatusForTesting(BoothStatus(
            state: .recording, updatedAt: now, installationState: .active
        ))
        store.applyStats(summary(booth: try inactive()))
        XCTAssertEqual(store.status?.lifecycleTitle, "Between exhibitions")
        store.applyStats(summary(booth: BoothStatus(
            state: .idle, updatedAt: Date(timeIntervalSince1970: 0),
            installationState: .active, isSynthetic: true
        )))
        XCTAssertEqual(store.status?.lifecycleTitle, "Waiting for booth")
        XCTAssertNil(store.status?.liveActivityState)
        store.apply(.status(BoothStatus(state: .dialTone, updatedAt: now)))
        XCTAssertEqual(store.status?.state, .dialTone)
        XCTAssertEqual(store.status?.installationState, .active)
        XCTAssertNil(store.status?.lifecycleTitle)
        XCTAssertEqual(store.history.count, 2)
    }

    @MainActor
    func testSocketInstallationEnvelopeEndsButMissingLifecycleDoesNotResume() throws {
        let store = BoothStatusLiveStore(client: .demo)
        let envelope = try OperatorJSON.decoder.decode(WsStatusEnvelope.self, from: Data("""
        {"kind":"installation","installation":{
          "id":"era-1","name":"First exhibition","startedAt":"2026-09-01T12:00:00Z",
          "endedAt":"2026-09-15T12:00:00Z","createdAt":"2026-09-01T12:00:00Z","isActive":false
        }}
        """.utf8))
        store.apply(envelope)
        XCTAssertEqual(store.status?.lifecycleTitle, "Between exhibitions")
        store.applyRESTStatusForTesting(BoothStatus(state: .idle, updatedAt: now))
        XCTAssertEqual(store.installationState, .betweenExhibitions)
    }

    @MainActor
    func testConfirmedLifecyclePersistsAcrossStoreCreationUntilExplicitRestart() throws {
        let suite = "installation-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BoothStatusLiveStore(client: .demo, lifecycleDefaults: defaults)
        store.applyRESTStatusForTesting(try inactive())
        let restored = BoothStatusLiveStore(client: .demo, lifecycleDefaults: defaults)
        XCTAssertEqual(restored.status?.lifecycleTitle, "Between exhibitions")
        restored.applyRESTStatusForTesting(BoothStatus(
            state: .idle, updatedAt: now, installationState: .active
        ))
        let resumed = BoothStatusLiveStore(client: .demo, lifecycleDefaults: defaults)
        XCTAssertEqual(resumed.installationState, .active)
        XCTAssertEqual(resumed.status?.lifecycleTitle, "Waiting for booth")
    }

    @MainActor
    func testAuthenticationFailureRemainsVisibleAndDoesNotInferInactive() async throws {
        let config = AppConfig.shared
        let previousDemoMode = config.isDemoMode
        config.isDemoMode = false
        defer { config.isDemoMode = previousDemoMode }
        let auth = AuthManager(keychainStore: TestKeychainStore())
        let client = OperatorClient(config: config, auth: auth)
        let unknown = BoothStatusLiveStore(client: client)
        await unknown.refreshNow()
        XCTAssertNil(unknown.installationState)
        XCTAssertNil(unknown.status)
        XCTAssertNotNil(unknown.lastError)
        XCTAssertEqual(unknown.connection, .offline)
        unknown.applyRESTStatusForTesting(try inactive())
        await unknown.refreshNow()
        XCTAssertEqual(unknown.installationState, .betweenExhibitions)
        XCTAssertNotNil(unknown.lastError)
    }

    func testLiveActivityContentSupportsLegacyAndInactiveWithoutTimer() throws {
        let legacy = try OperatorJSON.decoder.decode(CallInProgressAttributes.ContentState.self, from: Data("""
        {"boothState":"recording","startedAt":"2026-09-15T12:00:00Z"}
        """.utf8))
        XCTAssertTrue(legacy.showsCallTimer)
        XCTAssertNil(legacy.installationState)
        let inactive = CallInProgressAttributes.ContentState(
            boothState: "recording", startedAt: now, installationState: .betweenExhibitions
        )
        XCTAssertFalse(inactive.showsCallTimer)
        XCTAssertEqual(inactive.stateDisplayName, "Between exhibitions")
    }

    @MainActor
    func testInactivePreventsLiveActivityStartsUntilExplicitActive() {
        var requests = 0
        var ended: [InstallationState?] = []
        let manager = LiveActivityManager(activitiesEnabled: { true }, requestActivity: { _, _ in
            requests += 1
            return "test-activity"
        }, endActivities: { ended.append($0) })
        manager.setInstallationState(.betweenExhibitions)
        manager.setInstallationState(nil)
        XCTAssertEqual(ended, [.betweenExhibitions])
        manager.callStarted(sessionId: "inactive-test", boothName: "Test", boothState: "recording", startedAt: now)
        XCTAssertEqual(manager.installationState, .betweenExhibitions)
        XCTAssertEqual(requests, 0)
        manager.setInstallationState(.active)
        XCTAssertEqual(manager.installationState, .active)
        manager.callStarted(sessionId: "active-test", boothName: "Test", boothState: "recording", startedAt: now)
        XCTAssertEqual(requests, 1)
        manager.setInstallationState(.betweenExhibitions)
        XCTAssertEqual(ended, [.betweenExhibitions, .betweenExhibitions])
    }

    private func inactive() throws -> BoothStatus {
        try decodeStatus("""
        {"state":"idle","updatedAt":"1970-01-01T00:00:00.000Z",
         "isSynthetic":true,"installationState":"between_exhibitions"}
        """)
    }

    private func decodeStatus(_ json: String) throws -> BoothStatus {
        try OperatorJSON.decoder.decode(BoothStatus.self, from: Data(json.utf8))
    }

    private func summary(booth: BoothStatus) -> StatsSummary {
        StatsSummary(
            booth: booth, messages: DemoData.statsSummary.messages,
            calls: DemoData.statsSummary.calls, realtime: DemoData.statsSummary.realtime, generatedAt: now
        )
    }
}

final class InstallationNetworkTests: XCTestCase {
    @MainActor
    func testRESTPollingReconcilesLifecycleWhileSocketRemainsLive() async throws {
        let previousDemoMode = AppConfig.shared.isDemoMode
        AppConfig.shared.isDemoMode = false
        defer { AppConfig.shared.isDemoMode = previousDemoMode }
        let client = makeClient()
        LifecycleURLProtocol.response.withLock { $0 = .active }
        LifecycleURLProtocol.requestCounts.withLock { $0 = [:] }
        let store = BoothStatusLiveStore(client: client, socket: .demo)
        store.start()
        defer { store.stop() }
        try await waitUntil { store.connection == .live && store.installationState == .active }
        LifecycleURLProtocol.response.withLock { $0 = .inactive }
        try await waitUntil { store.installationState == .betweenExhibitions }
        XCTAssertEqual(store.connection, .live)
        XCTAssertEqual(store.status?.isSynthetic, true)
        XCTAssertFalse(store.history.contains { $0.isSynthetic == true })
        let counts = LifecycleURLProtocol.requestCounts.withLock { $0 }
        XCTAssertEqual(counts["/v1/status/history"], 1, "Live ticks must not fetch full history")
        XCTAssertEqual(counts["/v1/system/current"], 1, "Keep the cached live system snapshot")
        XCTAssertGreaterThanOrEqual(counts["/v1/status"] ?? 0, 2)
        LifecycleURLProtocol.response.withLock { $0 = .active }
        await store.refreshNow()
        XCTAssertEqual(store.installationState, .active)
        XCTAssertNil(store.lastError)
    }

    @MainActor
    func testHTTPAndNetworkFailuresDoNotImplyInactiveOrHideBehindSocketFrames() async throws {
        let previousDemoMode = AppConfig.shared.isDemoMode
        AppConfig.shared.isDemoMode = false
        defer { AppConfig.shared.isDemoMode = previousDemoMode }
        let client = makeClient()
        let store = BoothStatusLiveStore(client: client)
        for response in [LifecycleURLProtocol.Response.statusError(404), .statusError(409), .offline] {
            LifecycleURLProtocol.response.withLock { $0 = response }
            await store.refreshNow()
            XCTAssertNil(store.installationState)
            XCTAssertNotNil(store.lastError)
            store.apply(.status(BoothStatus(state: .idle, updatedAt: .now)))
            XCTAssertNotNil(store.lastError, "A healthy socket must not hide a failed REST request")
        }
        LifecycleURLProtocol.response.withLock { $0 = .inactive }
        await store.refreshNow()
        XCTAssertEqual(store.installationState, .betweenExhibitions)
        LifecycleURLProtocol.response.withLock { $0 = .offline }
        await store.refreshNow()
        XCTAssertEqual(store.installationState, .betweenExhibitions)
        XCTAssertNotNil(store.lastError)
    }

    @MainActor
    func testAPITransitionClearsFallbackAndRestoresOnlyNewServerLifecycle() async throws {
        let config = AppConfig.shared
        let previousURL = config.apiBaseURL
        let previousDemoMode = config.isDemoMode
        let suite = "installation-server-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            config.apiBaseURL = previousURL
            config.isDemoMode = previousDemoMode
            defaults.removePersistentDomain(forName: suite)
            LiveActivityManager.shared.resetInstallationState(nil)
        }
        config.isDemoMode = false
        let store = BoothStatusLiveStore(client: makeClient(), lifecycleDefaults: defaults)
        LifecycleURLProtocol.response.withLock { $0 = .inactive }
        await store.refreshNow()
        XCTAssertEqual(store.stats?.booth.installationState, .betweenExhibitions)
        let cachedURL = try XCTUnwrap(URL(string: "https://cached.example.test"))
        defaults.set("active", forKey: "boothInstallationState:\(cachedURL.absoluteString)")
        config.apiBaseURL = cachedURL
        LifecycleURLProtocol.response.withLock { $0 = .offline }
        await store.refreshNow()
        XCTAssertNil(store.stats)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertEqual(store.installationState, .active)
        XCTAssertEqual(LiveActivityManager.shared.installationState, .active)
        config.apiBaseURL = try XCTUnwrap(URL(string: "https://unknown.example.test"))
        await store.refreshNow()
        XCTAssertNil(store.status)
        XCTAssertNil(store.stats)
        XCTAssertNil(store.installationState)
        XCTAssertNil(LiveActivityManager.shared.installationState)
        XCTAssertNotNil(store.lastError)
    }

    @MainActor
    func makeClient() -> OperatorClient {
        let auth = AuthManager(keychainStore: TestKeychainStore())
        XCTAssertTrue(auth.storeTokens(OIDCTokens(
            accessToken: "test-access", refreshToken: "test-refresh", idToken: nil,
            expiresIn: 3600, tokenType: "Bearer"
        )))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LifecycleURLProtocol.self]
        return OperatorClient(config: .shared, auth: auth, session: URLSession(configuration: configuration))
    }

    @MainActor
    @nonobjc func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !predicate(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(predicate(), "Lifecycle did not reconcile within the REST polling interval")
    }
}

final class WidgetWriteThrottleTests: XCTestCase {
    func testSkippedWriteDoesNotMoveFreshnessDeadline() async {
        let clock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 2_000_000_000))
        let writes = OSAllocatedUnfairLock(initialState: 0)
        let coordinator = WidgetRefreshCoordinator(
            readSnapshot: { nil },
            writeSnapshot: { _ in
                writes.withLock { $0 += 1 }
                return true
            },
            now: { clock.withLock { $0 } }
        )
        _ = await coordinator.apply(stats: DemoData.statsSummary)
        clock.withLock { $0 += 30 }
        _ = await coordinator.apply(stats: DemoData.statsSummary)
        XCTAssertEqual(writes.withLock { $0 }, 1)
        clock.withLock { $0 += 31 }
        _ = await coordinator.apply(stats: DemoData.statsSummary)
        XCTAssertEqual(writes.withLock { $0 }, 2)
    }
}

actor WidgetSummaryGate {
    private var request: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation {
            request = $0
            observer?.resume()
            observer = nil
        }
    }

    func waitForRequest() async {
        if request != nil { return }
        await withCheckedContinuation { observer = $0 }
    }

    func release() {
        request?.resume()
        request = nil
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
