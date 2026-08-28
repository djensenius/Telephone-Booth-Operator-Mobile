//
//  PendingMessagesConcurrencyTests.swift
//

import XCTest
@testable import TBOperatorMobile

@MainActor
final class PendingMessagesConcurrencyTests: XCTestCase {
    func testNotificationCountSupersedesAnInFlightRefresh() async {
        let badgeRecorder = PendingBadgeRecorder()
        let statsGate = PendingStatsGate()
        let store = PendingMessagesStore(
            badgeSetter: { count in await badgeRecorder.set(count) },
            widgetStatsApplier: { _ in }
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
            widgetStatsApplier: { _ in }
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

    private func statsSummary(awaitingModeration: Int) -> StatsSummary {
        let stats = DemoData.statsSummary
        return StatsSummary(
            booth: stats.booth,
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
