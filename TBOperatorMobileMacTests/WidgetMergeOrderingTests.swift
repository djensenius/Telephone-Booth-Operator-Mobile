//
//  WidgetMergeOrderingTests.swift
//

import os
import XCTest
@testable import Operator

final class WidgetMergeOrderingTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 2_000_000_000)

    func testLaterHostEvaluationCannotHideNewerCriticalRouterSample() {
        let widget = health(temperature: 85, sample: 15, evaluation: 20)
        let cachedHost = health(temperature: 40, sample: 0, evaluation: 60)
        let merged = cachedHost.mergingNewerSections(from: widget)
        XCTAssertEqual(merged.systemHealth?.routerTemperatureCelsius, 85)
        XCTAssertEqual(merged.systemHealth?.severity, .critical)
        XCTAssertEqual(merged.systemHealth?.routerSourceUpdatedAt, base.addingTimeInterval(15))
        XCTAssertEqual(widget.mergingNewerSections(from: cachedHost), merged)
    }

    func testNewerRouterSampleAgesOutWithoutReplacingItsSourceClock() {
        let widget = health(temperature: 85, sample: 15, evaluation: 20)
        let cachedHost = health(temperature: 40, sample: 0, evaluation: 400)
        let merged = cachedHost.mergingNewerSections(from: widget)
        XCTAssertNil(merged.systemHealth?.routerTemperatureCelsius)
        XCTAssertNotEqual(merged.systemHealth?.severity, .critical)
        XCTAssertEqual(merged.systemHealth?.routerSourceUpdatedAt, base.addingTimeInterval(15))
        XCTAssertNil(merged.mergingNewerSections(from: widget).systemHealth?.routerTemperatureCelsius)
    }

    func testNewerBoothReportDoesNotDiscardNewerIndependentRouterData() {
        let widget = health(temperature: 85, sample: 15, evaluation: 20)
        let host = health(temperature: 40, sample: 0, evaluation: 60, booth: 1)
        let merged = host.mergingNewerSections(from: widget)
        XCTAssertEqual(merged.systemHealth?.sourceUpdatedAt, host.systemHealth?.sourceUpdatedAt)
        XCTAssertEqual(merged.systemHealth?.routerTemperatureCelsius, 85)
        XCTAssertEqual(merged.systemHealth?.severity, .critical)
    }

    func testNewerRouterObservationWithoutTemperatureClearsOlderSample() {
        let widget = health(temperature: 85, sample: 15, evaluation: 20)
        let absent = health(temperature: nil, sample: 30, evaluation: 40)
        let merged = absent.mergingNewerSections(from: widget)
        XCTAssertNil(merged.systemHealth?.routerTemperatureCelsius)
        XCTAssertNotEqual(merged.systemHealth?.severity, .critical)
        XCTAssertEqual(merged.systemHealth?.routerSourceUpdatedAt, base.addingTimeInterval(30))
    }

    func testConfirmedRouterAbsenceClearsOldSamplesWithoutLettingCachedAbsenceWin() {
        let widget = health(temperature: 85, sample: 15, evaluation: 20)
        let envelope = BoothSystemSnapshotEnvelope(
            boothId: DemoData.boothId,
            snapshot: BoothSystemSnapshot(temperatureCelsius: 45), receivedAt: base
        )
        let absent = WidgetSnapshot(systemHealth: .init(
            envelope: envelope, components: [], refreshedAt: base,
            evaluatedAt: base.addingTimeInterval(60), componentsObservedAt: base.addingTimeInterval(60)
        ))
        XCTAssertNil(absent.mergingNewerSections(from: widget).systemHealth?.routerTemperatureCelsius)
        let cachedAbsence = WidgetSnapshot(systemHealth: .init(
            envelope: envelope, components: [], refreshedAt: base,
            evaluatedAt: base.addingTimeInterval(60), componentsObservedAt: base
        ))
        XCTAssertEqual(cachedAbsence.mergingNewerSections(from: widget).systemHealth?.routerTemperatureCelsius, 85)
    }

    func testNewerRouterAbsenceObservationBypassesFreshnessThrottle() async {
        let envelope = BoothSystemSnapshotEnvelope(
            boothId: DemoData.boothId,
            snapshot: BoothSystemSnapshot(temperatureCelsius: 45), receivedAt: base
        )
        let cache = OSAllocatedUnfairLock(initialState: WidgetSnapshot(
            summary: .init(stats: stats(generated: 0, count: 1)),
            systemHealth: .init(envelope: envelope, components: [], refreshedAt: base, componentsObservedAt: base),
            writtenAt: base
        ))
        let writes = OSAllocatedUnfairLock(initialState: 0)
        let after = base.addingTimeInterval(5)
        let coordinator = WidgetRefreshCoordinator(
            readSnapshot: { cache.withLock { $0 } },
            writeSnapshot: { snapshot in
                writes.withLock { $0 += 1 }
                cache.withLock { $0 = snapshot }
                return true
            }, now: { after }
        )
        _ = await coordinator.apply(stats: stats(generated: 0, count: 1), systemEnvelope: envelope, components: [],
                                    systemObservedAt: base, componentsObservedAt: after)
        XCTAssertEqual(writes.withLock { $0 }, 1)
        XCTAssertEqual(cache.withLock { $0.systemHealth?.routerObservedAt }, after)
    }

    func testCountsAndBoothStateUseIndependentSourceVersions() throws {
        let initial = WidgetSnapshot.Summary(stats: stats(generated: 0, count: 1))
        let countOnly = initial.replacingCounts(with: stats(generated: 20, count: 99))
        let state = WidgetSnapshot.Summary(stats: stats(generated: 10, count: 2, state: .recording, booth: 30))
        let merged = WidgetSnapshot(summary: state).mergingNewerSections(from: WidgetSnapshot(summary: countOnly))
        XCTAssertEqual(merged.summary?.boothState, .recording)
        XCTAssertEqual(merged.summary?.pendingMessages, 99)
        XCTAssertEqual(merged.summary?.countsSourceGeneratedAt, base.addingTimeInterval(20))
        XCTAssertEqual(merged.summary?.sourceGeneratedAt, base.addingTimeInterval(10))
        let roundTrip = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(merged))
        XCTAssertEqual(roundTrip, merged)
    }

    func testNewerCountResponseCannotRegressAnAlreadyNewerBoothEvent() {
        let live = WidgetSnapshot.Summary(stats: stats(generated: 10, count: 1, state: .recording, booth: 30))
        let rest = WidgetSnapshot.Summary(stats: stats(generated: 40, count: 5, state: .idle, booth: 20))
        let merged = WidgetSnapshot(summary: rest).mergingNewerSections(from: WidgetSnapshot(summary: live))
        XCTAssertEqual(merged.summary?.boothState, .recording)
        XCTAssertEqual(merged.summary?.boothUpdatedAt, base.addingTimeInterval(30))
        XCTAssertEqual(merged.summary?.pendingMessages, 5)
        XCTAssertEqual(merged.summary?.countsSourceGeneratedAt, base.addingTimeInterval(40))
    }

    func testNewerUnchangedCountVersionIsPersistedAndRejectsOlderCounts() async {
        let initial = WidgetSnapshot.Summary(stats: stats(generated: 0, count: 99))
            .replacingCounts(with: stats(generated: 20, count: 99))
        let cache = OSAllocatedUnfairLock(initialState: WidgetSnapshot(summary: initial, writtenAt: base))
        let writes = OSAllocatedUnfairLock(initialState: 0)
        let coordinator = WidgetRefreshCoordinator(
            readSnapshot: { cache.withLock { $0 } },
            writeSnapshot: { snapshot in
                writes.withLock { $0 += 1 }
                cache.withLock { $0 = snapshot }
                return true
            }, now: { Date(timeIntervalSince1970: 2_000_000_005) }
        )
        _ = await coordinator.applyCounts(stats: stats(generated: 25, count: 99),
                                          apiRevision: WidgetRefreshCoordinator.currentAPIRevision)
        XCTAssertEqual(writes.withLock { $0 }, 1)
        XCTAssertEqual(cache.withLock { $0.summary?.countsSourceGeneratedAt }, base.addingTimeInterval(25))
        _ = await coordinator.applyCounts(stats: stats(generated: 22, count: 1),
                                          apiRevision: WidgetRefreshCoordinator.currentAPIRevision)
        XCTAssertEqual(writes.withLock { $0 }, 1)
        XCTAssertEqual(cache.withLock { $0.summary?.pendingMessages }, 99)
    }

    func testUnchangedNonemptyMessageConfirmationPersistsItsOrderingFence() async {
        let message = DemoData.messages[0]
        let latest = WidgetSnapshot.LatestMessage(message: message, refreshedAt: base)
        let summary = stats(generated: 0, count: 1)
        let cache = OSAllocatedUnfairLock(initialState: WidgetSnapshot(
            summary: .init(stats: summary), latestMessage: latest, writtenAt: base
        ))
        let writes = OSAllocatedUnfairLock(initialState: 0)
        let after = base.addingTimeInterval(5)
        let coordinator = WidgetRefreshCoordinator(
            readSnapshot: { cache.withLock { $0 } },
            writeSnapshot: { snapshot in
                writes.withLock { $0 += 1 }
                cache.withLock { $0 = snapshot }
                return true
            }, now: { after }
        )
        _ = await coordinator.refresh(using: StableMessageWidgetClient(stats: summary, message: message))
        XCTAssertEqual(writes.withLock { $0 }, 1)
        XCTAssertEqual(cache.withLock { $0.latestMessageRefreshedAt }, after)
        let staleStatus: MessageStatus = message.status == .approved ? .rejected : .approved
        let stale = WidgetSnapshot(latestMessage: .init(
            id: message.id, status: staleStatus, occurredAt: latest.occurredAt,
            refreshedAt: base.addingTimeInterval(3)
        ))
        let merged = stale.mergingNewerSections(from: cache.withLock { $0 })
        XCTAssertEqual(merged.latestMessage?.status, message.status)
    }

    private func health(temperature: Double?, sample: TimeInterval, evaluation: TimeInterval,
                        booth: TimeInterval = 0) -> WidgetSnapshot {
        let sourceDate = base.addingTimeInterval(booth)
        let envelope = BoothSystemSnapshotEnvelope(
            boothId: DemoData.boothId,
            snapshot: BoothSystemSnapshot(
                cpu: .init(physicalCores: 4, loadAvg1m: 0.5), temperatureCelsius: 45,
                memory: .init(totalBytes: 1_000, usedBytes: 400), tailscale: .init(connected: true)
            ), receivedAt: sourceDate
        )
        let router = SystemComponentCurrentEnvelope(
            source: DemoData.systemComponentSources[0].source,
            latestSnapshot: .init(battery: .init(temperatureCelsius: temperature)),
            capturedAt: base.addingTimeInterval(sample), receivedAt: base.addingTimeInterval(sample)
        )
        return WidgetSnapshot(systemHealth: .init(
            envelope: envelope, components: [router], refreshedAt: sourceDate,
            evaluatedAt: base.addingTimeInterval(evaluation),
            componentsObservedAt: base.addingTimeInterval(evaluation)
        ), writtenAt: base.addingTimeInterval(evaluation))
    }

    private func stats(generated: TimeInterval, count: Int, state: BoothState = .idle,
                       booth: TimeInterval = 0) -> StatsSummary {
        let initial = DemoData.statsSummary
        return StatsSummary(
            booth: BoothStatus(state: state, updatedAt: base.addingTimeInterval(booth)),
            messages: .init(pending: count, awaitingModeration: count, receivedToday: count, latestId: nil),
            calls: initial.calls, realtime: initial.realtime, generatedAt: base.addingTimeInterval(generated)
        )
    }
}

private struct StableMessageWidgetClient: WidgetDataFetching {
    let stats: StatsSummary
    let message: Message

    func fetchStatsSummary(timeZone: TimeZone) async throws -> StatsSummary { stats }
    func fetchMessages(status: MessageStatus?, since: Date?, limit: Int) async throws -> MessageList {
        MessageList(items: [message])
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
