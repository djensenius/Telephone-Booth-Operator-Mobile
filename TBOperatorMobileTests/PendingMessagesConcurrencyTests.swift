//
//  PendingMessagesConcurrencyTests.swift
//

import XCTest
import os
@testable import TBOperatorMobile

@MainActor
final class PendingMessagesConcurrencyTests: XCTestCase {
    func testAPISwitchClearsExistingBadgeEvenWhenNewRefreshFails() async {
        let recorder = PendingBadgeRecorder(blockFirstWrite: true)
        let store = PendingMessagesStore(
            badgeSetter: { count in await recorder.set(count) }, widgetStatsApplier: { _, _ in }
        )
        let oldWrite = Task { await store.applyNotificationCount(9) }
        await recorder.waitUntilFirstWriteStarted()
        WidgetRefreshCoordinator.invalidateAPIBase()
        store.resetForAPIChange()
        XCTAssertEqual(store.pendingCount, 0)
        await store.refresh { throw URLError(.notConnectedToInternet) }
        await recorder.waitUntilValueIsRecorded(0)
        await recorder.releaseFirstWrite()
        await oldWrite.value
        let lastBadge = await recorder.values.last
        XCTAssertEqual(lastBadge, 0)
    }

    func testNotificationCountSupersedesAnInFlightRefresh() async {
        let badgeRecorder = PendingBadgeRecorder()
        let statsGate = PendingStatsGate()
        let store = PendingMessagesStore(
            badgeSetter: { count in await badgeRecorder.set(count) },
            widgetStatsApplier: { _, _ in }
        )
        let refresh = Task {
            await store.refresh {
                await statsGate.fetch()
            }

        }
        await statsGate.waitUntilStarted()

        await store.applyNotificationCount(7)
        await statsGate.complete(with: statsSummary(awaitingModeration: 2))
        await refresh.value

        XCTAssertEqual(store.pendingCount, 7)
        let lastBadge = await badgeRecorder.values.last
        XCTAssertEqual(lastBadge, 7)
    }

    func testStaleBadgeWriteFinishesByReapplyingTheNewestCount() async {
        let badgeRecorder = PendingBadgeRecorder(blockFirstWrite: true)
        let store = PendingMessagesStore(
            badgeSetter: { count in await badgeRecorder.set(count) },
            widgetStatsApplier: { _, _ in }
        )
        let first = Task { await store.applyNotificationCount(1) }
        await badgeRecorder.waitUntilFirstWriteStarted()
        let second = Task { await store.applyNotificationCount(2) }
        await badgeRecorder.waitUntilValueIsRecorded(2)
        await badgeRecorder.releaseFirstWrite()
        await first.value
        await second.value

        XCTAssertEqual(store.pendingCount, 2)
        let lastBadge = await badgeRecorder.values.last
        XCTAssertEqual(lastBadge, 2)
    }

    func testOldAPISummaryCannotUpdateBadgeOrWidgets() async {
        let recorder = PendingBadgeRecorder()
        let statsGate = PendingStatsGate()
        let store = PendingMessagesStore(
            badgeSetter: { count in await recorder.set(count) },
            widgetStatsApplier: { stats, _ in await recorder.set(stats.messages.badgeCount) }
        )
        let refresh = Task { await store.refresh { await statsGate.fetch() } }
        await statsGate.waitUntilStarted()
        WidgetRefreshCoordinator.invalidateAPIBase()
        await statsGate.complete(with: statsSummary(awaitingModeration: 99))
        await refresh.value
        let writes = await recorder.values
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(store.pendingCount, 0)
    }

    func testCountOnlyAndDelayedUpdatesCannotReverseConfirmedDowntime() async {
        let snapshot = OSAllocatedUnfairLock(initialState: WidgetSnapshot?.none)
        let coordinator = WidgetRefreshCoordinator(
            readSnapshot: { snapshot.withLock { $0 } },
            writeSnapshot: { updated in snapshot.withLock { $0 = updated }; return true }
        )
        let observedAt = Date().addingTimeInterval(-10)
        let inactive = statsSummary(awaitingModeration: 2, booth: BoothStatus(
            state: .idle, updatedAt: Date(timeIntervalSince1970: 0),
            installationState: .betweenExhibitions, isSynthetic: true
        ))
        _ = await coordinator.apply(
            stats: inactive, systemEnvelope: nil, components: [], observedAt: observedAt
        )
        let active = statsSummary(awaitingModeration: 7, booth: BoothStatus(
            state: .recording, updatedAt: observedAt, installationState: .active
        ))
        _ = await coordinator.applyCounts(stats: active, apiRevision: WidgetRefreshCoordinator.currentAPIRevision)
        XCTAssertEqual(snapshot.withLock { $0?.summary?.pendingMessages }, 7)
        XCTAssertEqual(snapshot.withLock { $0?.summary?.installationState }, .betweenExhibitions)
        XCTAssertEqual(LiveActivityManager.shared.installationState, .betweenExhibitions)
        XCTAssertEqual(snapshot.withLock { $0?.summary?.refreshedAt }, observedAt)
        XCTAssertEqual(snapshot.withLock { $0?.summary?.sourceGeneratedAt }, inactive.generatedAt)
        _ = await coordinator.apply(
            stats: active, systemEnvelope: nil, components: [],
            observedAt: observedAt.addingTimeInterval(-1)
        )
        XCTAssertEqual(snapshot.withLock { $0?.summary?.installationState }, .betweenExhibitions)
        _ = await coordinator.apply(
            stats: active, systemEnvelope: nil, components: [],
            observedAt: observedAt.addingTimeInterval(1)
        )
        XCTAssertEqual(snapshot.withLock { $0?.summary?.installationState }, .active)
    }

    func testOldSocketFrameIsDiscardedAtAPIBoundary() {
        let previousURL = AppConfig.shared.apiBaseURL
        defer { AppConfig.shared.apiBaseURL = previousURL }
        let store = BoothStatusLiveStore(client: .demo)
        store.applyStats(statsSummary(awaitingModeration: 2))
        BoothStatusLiveStore.shared.applyStats(statsSummary(awaitingModeration: 2))
        AppConfig.shared.apiBaseURL = previousURL.appendingPathComponent("different-api")
        XCTAssertNil(BoothStatusLiveStore.shared.stats, "API changes must clear data before any poll or frame")
        XCTAssertNil(BoothStatusLiveStore.shared.status)
        store.apply(.status(BoothStatus(state: .recording, updatedAt: .now)))
        XCTAssertNil(store.status)
        XCTAssertNil(store.stats)
        XCTAssertNil(store.installationState)
    }

    func testOldAPIEventCannotStartLiveActivity() {
        var requests = 0
        let manager = LiveActivityManager(activitiesEnabled: { true }, requestActivity: { _, _ in
            requests += 1
            return "test"
        })
        let observer = LiveActivityEventObserver(manager: manager)
        let revision = WidgetRefreshCoordinator.currentAPIRevision
        let event = BoothEventRecord(
            id: "event", eventId: "event", boothId: "booth", bootId: "boot",
            type: .callStarted, occurredAt: .now, receivedAt: .now,
            sessionId: "session", recordingId: nil, version: nil
        )
        WidgetRefreshCoordinator.invalidateAPIBase()
        observer.handleEvent(event, apiRevision: revision)
        XCTAssertEqual(requests, 0)
        BoothStatusLiveStore.shared.applyRESTStatusForTesting(
            BoothStatus(state: .idle, updatedAt: .now, installationState: .active)
        )
        observer.handleEvent(event, apiRevision: WidgetRefreshCoordinator.currentAPIRevision)
        XCTAssertEqual(requests, 1)
    }

    private func statsSummary(awaitingModeration: Int, booth: BoothStatus? = nil) -> StatsSummary {
        let stats = DemoData.statsSummary
        return StatsSummary(
            booth: booth ?? stats.booth,
            messages: .init(
                pending: awaitingModeration,
                awaitingModeration: awaitingModeration,
                receivedToday: stats.messages.receivedToday,
                latestId: stats.messages.latestId
            ),
            calls: stats.calls,
            interactions: stats.interactions,
            actions: stats.actions,
            realtime: stats.realtime,
            generatedAt: stats.generatedAt,
            dayStartedAt: stats.dayStartedAt,
            timeZone: stats.timeZone
        )
    }
}

private actor PendingStatsGate {
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<StatsSummary, Never>?

    func fetch() async -> StatsSummary {
        started = true
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
        return await withCheckedContinuation { resultContinuation = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func complete(with stats: StatsSummary) {
        resultContinuation?.resume(returning: stats)
        resultContinuation = nil
    }
}

private actor PendingBadgeRecorder {
    private(set) var values: [Int] = []
    private let blockFirstWrite: Bool
    private var writeCount = 0
    private var firstWriteStarted = false
    private var firstWriteWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstWriteContinuation: CheckedContinuation<Void, Never>?
    private var valueWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(blockFirstWrite: Bool = false) {
        self.blockFirstWrite = blockFirstWrite
    }

    func set(_ count: Int) async {
        writeCount += 1
        if blockFirstWrite, writeCount == 1 {
            firstWriteStarted = true
            firstWriteWaiters.forEach { $0.resume() }
            firstWriteWaiters.removeAll()
            await withCheckedContinuation { firstWriteContinuation = $0 }
        }
        values.append(count)
        let ready = valueWaiters.filter { $0.0 == count }
        valueWaiters.removeAll { $0.0 == count }
        ready.forEach { $0.1.resume() }
    }

    func waitUntilFirstWriteStarted() async {
        if firstWriteStarted { return }
        await withCheckedContinuation { firstWriteWaiters.append($0) }
    }

    func waitUntilValueIsRecorded(_ value: Int) async {
        if values.contains(value) { return }
        await withCheckedContinuation { valueWaiters.append((value, $0)) }
    }

    func releaseFirstWrite() {
        firstWriteContinuation?.resume()
        firstWriteContinuation = nil
    }
}

extension InstallationNetworkTests {
    @MainActor
    func testAPIChangeWhileLiveRestartsFullSeedWithoutWaitingForOldRequest() async throws {
        let config = AppConfig.shared
        let previousURL = config.apiBaseURL
        let previousDemoMode = config.isDemoMode
        config.isDemoMode = false
        defer {
            config.apiBaseURL = previousURL
            config.isDemoMode = previousDemoMode
        }
        LifecycleURLProtocol.response.withLock { $0 = .active }
        LifecycleURLProtocol.requestCounts.withLock { $0 = [:] }
        let store = BoothStatusLiveStore(client: makeClient(), socket: .demo)
        store.start()
        defer { store.stop() }
        try await waitUntil { store.connection == .live && store.installationState == .active }
        LifecycleURLProtocol.holdNextStatus.withLock { $0 = true }
        let oldRefresh = Task { await store.refreshNow() }
        try await waitUntil { LifecycleURLProtocol.heldStatus.withLock { $0 != nil } }
        config.apiBaseURL = previousURL.appendingPathComponent("new-api")
        store.synchronizeAPIBase()
        let historyPath = config.apiBaseURL.path + "/v1/status/history"
        try await waitUntil {
            store.connection == .live && store.installationState == .active
                && LifecycleURLProtocol.requestCounts.withLock { $0[historyPath, default: 0] > 0 }
        }
        LifecycleURLProtocol.releaseStatus(as: .inactive)
        await oldRefresh.value
        XCTAssertEqual(store.installationState, .active)
    }

    @MainActor
    func testOverlappingRESTResultsCannotReplaceNewerConnectionOutcome() async throws {
        let previousDemoMode = AppConfig.shared.isDemoMode
        AppConfig.shared.isDemoMode = false
        defer { AppConfig.shared.isDemoMode = previousDemoMode }
        let store = BoothStatusLiveStore(client: makeClient())
        for latestFails in [true, false] {
            LifecycleURLProtocol.response.withLock { $0 = .active }
            LifecycleURLProtocol.holdNextStatus.withLock { $0 = true }
            let oldRefresh = Task { await store.refreshNow() }
            try await waitUntil { LifecycleURLProtocol.heldStatus.withLock { $0 != nil } }
            LifecycleURLProtocol.response.withLock { $0 = latestFails ? .statusError(409) : .active }
            await store.refreshNow()
            XCTAssertEqual(store.lastError != nil, latestFails)
            LifecycleURLProtocol.releaseStatus(as: latestFails ? .active : .statusError(409))
            await oldRefresh.value
            XCTAssertEqual(store.lastError != nil, latestFails)
        }
    }
}

final class LifecycleURLProtocol: URLProtocol {
    enum Response: Sendable, Equatable {
        case active, inactive, offline
        case statusError(Int)
    }
    static let response = OSAllocatedUnfairLock(initialState: Response.active)
    static let requestCounts = OSAllocatedUnfairLock(initialState: [String: Int]())
    static let holdNextStatus = OSAllocatedUnfairLock(initialState: false)
    final class HeldRequest: @unchecked Sendable {
        let value: LifecycleURLProtocol
        init(_ value: LifecycleURLProtocol) { self.value = value }
    }
    static let heldStatus = OSAllocatedUnfairLock(initialState: HeldRequest?.none)

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    static func releaseStatus(as scenario: Response) {
        let held = heldStatus.withLock { value in
            defer { value = nil }
            return value
        }
        held?.value.complete(scenario)
    }

    override func startLoading() {
        if let path = request.url?.path {
            Self.requestCounts.withLock { $0[path, default: 0] += 1 }
            if path.hasSuffix("/v1/status"), Self.holdNextStatus.withLock({ value in
                defer { value = false }
                return value
            }) {
                let held = HeldRequest(self)
                Self.heldStatus.withLock { $0 = held }
                return
            }
        }
        complete(Self.response.withLock { $0 })
    }

    private func complete(_ scenario: Response) {
        guard scenario != .offline, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        do {
            var code = 200
            var body = Data(#"{"items":[]}"#.utf8)
            if url.path.hasSuffix("/v1/status") {
                if case .statusError(let status) = scenario {
                    code = status
                    body = Data(#"{"error":"installation_inactive"}"#.utf8)
                } else {
                    body = try OperatorJSON.encoder.encode(BoothStatus(
                        state: .idle, updatedAt: Date(timeIntervalSince1970: 0),
                        installationState: scenario == .inactive ? .betweenExhibitions : .active,
                        isSynthetic: true
                    ))
                }
            } else if url.path.hasSuffix("/v1/stats/summary") {
                body = try OperatorJSON.encoder.encode(DemoData.statsSummary)
            }
            guard let response = HTTPURLResponse(
                url: url, statusCode: code, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": code == 409 ? "application/problem+json" : "application/json"]
            ) else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
