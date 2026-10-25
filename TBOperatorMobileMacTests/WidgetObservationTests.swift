//
//  WidgetObservationTests.swift
//

import os
import XCTest
@testable import Operator

final class WidgetObservationTests: XCTestCase {
    func testCrossWriterLeaseCoversFetchingAndPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstProbe = WidgetObservationProbe(paused: true)
        let secondProbe = WidgetObservationProbe(paused: false)
        let first = coordinator(directory: directory)
        let second = coordinator(directory: directory)
        let firstTask = Task { await first.refresh(using: ObservationClient(probe: firstProbe)) }
        defer { firstTask.cancel(); Task { await firstProbe.release() } }
        try await waitUntilStarted(firstProbe)
        // Deterministically verify the descriptor is still held while a request
        // is paused (e.g. during authentication), not just around the file write.
        XCTAssertThrowsError(try MacWidgetFileLock.acquire(
            name: "observations.lock", wait: false, directoryURL: directory
        ))
        let secondTask = Task { await second.refresh(using: ObservationClient(probe: secondProbe)) }
        defer { secondTask.cancel() }
        try await Task.sleep(for: .milliseconds(30))
        let startedEarly = await secondProbe.started
        XCTAssertFalse(startedEarly)
        await firstProbe.release()
        let firstResult = await firstTask.value
        let secondResult = await secondTask.value
        XCTAssertNotEqual(firstResult, .failed)
        XCTAssertNotEqual(secondResult, .failed)
        let startedAfterRelease = await secondProbe.started
        XCTAssertTrue(startedAfterRelease)
    }

    func testSignOutCancelsARefreshWaitingForTheObservationLease() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lease = try MacWidgetFileLock.acquire(name: "observations.lock", wait: false, directoryURL: directory)
        defer { withExtendedLifetime(lease) {} }
        let probe = WidgetObservationProbe(paused: false)
        let coordinator = coordinator(directory: directory)
        let task = Task { await coordinator.refresh(using: ObservationClient(probe: probe)) }
        try await Task.sleep(for: .milliseconds(30))
        _ = await coordinator.clear()
        let result = await task.value
        let started = await probe.started
        XCTAssertEqual(result, .failed)
        XCTAssertFalse(started)
    }

    @MainActor
    func testDemoCountsNeverPublishWidgetStats() async {
        let writes = OSAllocatedUnfairLock(initialState: 0)
        let store = PendingMessagesStore(badgeSetter: { _ in }, widgetStatsApplier: { _, _ in
            writes.withLock { $0 += 1 }
        })
        await store.refresh(using: .demo)
        XCTAssertGreaterThan(store.pendingCount, 0)
        XCTAssertEqual(writes.withLock { $0 }, 0)
    }

    @MainActor
    func testChangingPollingClientsReplacesTheOldSourceButSameClientDoesNot() async throws {
        let badges = OSAllocatedUnfairLock(initialState: 0)
        let store = PendingMessagesStore(badgeSetter: { _ in badges.withLock { $0 += 1 } },
                                         widgetStatsApplier: { _, _ in })
        defer { store.stopPolling() }
        store.startPolling(using: .demo)
        for _ in 0..<500 {
            if badges.withLock({ $0 }) >= 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(badges.withLock { $0 }, 1)
        store.startPolling(using: .demo)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(badges.withLock { $0 }, 1)
        let replacement = OperatorClient(config: .shared, auth: .shared, demoMode: true)
        store.startPolling(using: replacement)
        for _ in 0..<500 {
            if badges.withLock({ $0 }) >= 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(badges.withLock { $0 }, 2)
    }

    private func coordinator(directory: URL) -> WidgetRefreshCoordinator {
        WidgetRefreshCoordinator(
            readSnapshot: { nil }, writeSnapshot: { _ in true }, clearSnapshot: { true },
            observationLease: {
                for _ in 0..<500 {
                    try Task.checkCancellation()
                    if let lease = try? MacWidgetFileLock.acquire(
                        name: "observations.lock", wait: false, directoryURL: directory
                    ) { return lease }
                    try await Task.sleep(for: .milliseconds(10))
                }
                throw URLError(.timedOut)
            }
        )
    }

    private func waitUntilStarted(_ probe: WidgetObservationProbe) async throws {
        for _ in 0..<500 {
            if await probe.started { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Observation did not start")
        throw URLError(.timedOut)
    }
}

private actor WidgetObservationProbe {
    private(set) var started = false
    private let paused: Bool
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(paused: Bool) { self.paused = paused }

    func summary() async -> StatsSummary {
        started = true
        if paused, !released {
            await withCheckedContinuation { continuation = $0 }
        }
        return DemoData.statsSummary
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private struct ObservationClient: WidgetDataFetching {
    let probe: WidgetObservationProbe
    func fetchStatsSummary(timeZone: TimeZone) async throws -> StatsSummary { await probe.summary() }
    func fetchMessages(status: MessageStatus?, since: Date?, limit: Int) async throws -> MessageList {
        throw URLError(.notConnectedToInternet)
    }
    func fetchStatsOverview(window: StatsWindow) async throws -> StatsOverview {
        throw URLError(.notConnectedToInternet)
    }
    func fetchCurrentSystemEnvelope(boothId: String?) async throws -> BoothSystemSnapshotEnvelope? {
        throw URLError(.notConnectedToInternet)
    }
    func fetchCurrentSystemComponents() async throws -> [SystemComponentCurrentEnvelope] {
        throw URLError(.notConnectedToInternet)
    }
}
