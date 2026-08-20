//
//  WidgetRefreshCoordinator.swift
//  TelephoneBoothOperatorMobile
//

import Foundation
import os

public protocol WidgetDataFetching: Sendable {
    func fetchStatsSummary(timeZone: TimeZone) async throws -> StatsSummary
    func fetchStatsOverview(window: StatsWindow) async throws -> StatsOverview
    func fetchMessages(
        status: MessageStatus?,
        since: Date?,
        limit: Int
    ) async throws -> MessageList
    func fetchCurrentSystemEnvelope(
        boothId: String?
    ) async throws -> BoothSystemSnapshotEnvelope?
    func fetchCurrentSystemComponents() async throws -> [SystemComponentCurrentEnvelope]
}

extension OperatorClient: WidgetDataFetching {}

public enum WidgetRefreshResult: Sendable, Equatable {
    case newData
    case noData
    case failed
}

public actor WidgetRefreshCoordinator {
    public static let shared = WidgetRefreshCoordinator()
    private static let minimumFreshnessWriteInterval: TimeInterval = 60

    private let readSnapshot: @Sendable () -> WidgetSnapshot?
    private let writeSnapshot: @Sendable (WidgetSnapshot) -> Bool
    private let clearSnapshot: @Sendable () -> Bool
    private let now: @Sendable () -> Date
    private var cachedSnapshot: WidgetSnapshot?
    private var hasLoadedSnapshot = false
    private var generation: UInt = 0
    private var acceptsUpdates = true
    private var activeRefresh: Task<WidgetRefreshResult, Never>?
    private var activeRefreshID: UInt = 0

    private let logger = Logger(
        subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
        category: "WidgetRefresh"
    )

    public init(
        readSnapshot: @escaping @Sendable () -> WidgetSnapshot? = {
            WidgetSnapshotStore.read()
        },
        writeSnapshot: @escaping @Sendable (WidgetSnapshot) -> Bool = {
            WidgetSnapshotStore.write($0)
        },
        clearSnapshot: @escaping @Sendable () -> Bool = {
            WidgetSnapshotStore.clear()
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.readSnapshot = readSnapshot
        self.writeSnapshot = writeSnapshot
        self.clearSnapshot = clearSnapshot
        self.now = now
    }

    @discardableResult
    public func apply(stats: StatsSummary) -> WidgetRefreshResult {
        apply(stats: stats, systemEnvelope: nil, components: [])
    }

    @discardableResult
    public func apply(
        stats: StatsSummary,
        systemEnvelope: BoothSystemSnapshotEnvelope?,
        components: [SystemComponentCurrentEnvelope]
    ) -> WidgetRefreshResult {
        guard acceptsUpdates else { return .failed }
        let previous = snapshot()
        let refreshDate = now()
        let candidateSummary = WidgetSnapshot.Summary(
            stats: stats,
            refreshedAt: refreshDate
        )
        let summary: WidgetSnapshot.Summary
        if let current = previous.summary,
           summaryIsNewer(current, than: candidateSummary) {
            summary = current
        } else {
            summary = candidateSummary
        }

        let candidateHealth = systemEnvelope.map {
            WidgetSnapshot.SystemHealth(
                envelope: $0,
                components: components,
                refreshedAt: refreshDate
            )
        }
        let health: WidgetSnapshot.SystemHealth?
        if let current = previous.systemHealth,
           let candidateHealth,
           current.sourceUpdatedAt > candidateHealth.sourceUpdatedAt {
            health = current
        } else {
            health = candidateHealth ?? previous.systemHealth
        }
        let updated = WidgetSnapshot(
            summary: summary,
            latestMessage: previous.latestMessage,
            systemHealth: health,
            activity: previous.activity,
            writtenAt: refreshDate
        )
        return persist(updated, replacing: previous)
    }

    public func refresh(
        using client: any WidgetDataFetching,
        timeZone: TimeZone = .current
    ) async -> WidgetRefreshResult {
        guard acceptsUpdates else { return .failed }
        if let activeRefresh {
            return await activeRefresh.value
        }
        let task = Task { [weak self] in
            guard let self else { return WidgetRefreshResult.failed }
            return await self.performRefresh(using: client, timeZone: timeZone)
        }
        activeRefreshID &+= 1
        let refreshID = activeRefreshID
        activeRefresh = task
        let result = await task.value
        if activeRefreshID == refreshID {
            activeRefresh = nil
        }
        return result
    }

    private func performRefresh(
        using client: any WidgetDataFetching,
        timeZone: TimeZone
    ) async -> WidgetRefreshResult {
        guard acceptsUpdates else { return .failed }
        let refreshGeneration = generation
        let refreshDate = now()

        async let summaryResult = captureWidgetFetch {
            try await client.fetchStatsSummary(timeZone: timeZone)
        }
        async let latestMessageResult = captureWidgetFetch {
            try await client.fetchMessages(status: nil, since: nil, limit: 1).items.first
        }
        async let systemResult = captureWidgetFetch {
            try await client.fetchCurrentSystemEnvelope(boothId: nil)
        }
        async let componentsResult = captureWidgetFetch {
            try await client.fetchCurrentSystemComponents()
        }
        async let activityResult = captureWidgetFetch {
            try await client.fetchStatsOverview(window: .last24h)
        }

        let results = await (
            summaryResult,
            latestMessageResult,
            systemResult,
            componentsResult,
            activityResult
        )
        guard acceptsUpdates, generation == refreshGeneration else {
            return .failed
        }
        let previous = snapshot()
        let summary = resolveSummary(
            results.0,
            current: previous.summary,
            refreshedAt: refreshDate
        )
        let latestMessage = resolveLatestMessage(
            results.1,
            current: previous.latestMessage,
            refreshedAt: refreshDate
        )
        let components = resolveComponents(results.3)
        let systemHealth = resolveSystemHealth(
            results.2,
            components: components.value,
            current: previous.systemHealth,
            refreshedAt: refreshDate
        )
        let activity = resolveActivity(
            results.4,
            current: previous.activity,
            refreshedAt: refreshDate
        )
        let succeeded = [
            summary.succeeded,
            latestMessage.succeeded,
            components.succeeded,
            systemHealth.succeeded,
            activity.succeeded
        ].filter { $0 }.count

        guard succeeded > 0 else { return .failed }

        let updated = WidgetSnapshot(
            summary: summary.value,
            latestMessage: latestMessage.value,
            systemHealth: systemHealth.value,
            activity: activity.value,
            writtenAt: refreshDate
        )
        return persist(updated, replacing: previous)
    }

    @discardableResult
    public func clear() -> Bool {
        acceptsUpdates = false
        generation &+= 1
        activeRefresh?.cancel()
        activeRefreshID &+= 1
        activeRefresh = nil
        cachedSnapshot = nil
        hasLoadedSnapshot = true
        return clearSnapshot()
    }

    public func activate() {
        acceptsUpdates = true
    }

    public func cancelActiveRefresh() {
        generation &+= 1
        activeRefresh?.cancel()
        activeRefreshID &+= 1
        activeRefresh = nil
    }

    private func snapshot() -> WidgetSnapshot {
        if !hasLoadedSnapshot {
            cachedSnapshot = readSnapshot()
            hasLoadedSnapshot = true
        }
        return cachedSnapshot ?? WidgetSnapshot(writtenAt: now())
    }

    private func persist(
        _ updated: WidgetSnapshot,
        replacing previous: WidgetSnapshot
    ) -> WidgetRefreshResult {
        let hasNewContent = !previous.hasSameContent(as: updated)
        let timeSinceWrite = updated.writtenAt.timeIntervalSince(previous.writtenAt)
        if !hasNewContent, timeSinceWrite < Self.minimumFreshnessWriteInterval {
            return .noData
        }
        guard writeSnapshot(updated) else {
            logger.error("Failed to persist refreshed widget snapshot")
            return .failed
        }
        cachedSnapshot = updated
        return hasNewContent ? .newData : .noData
    }

    private func logFailure(endpoint: String, message: String) {
        logger.warning(
            "Widget refresh failed for \(endpoint, privacy: .public): \(message, privacy: .public)"
        )
    }

    private func resolveSummary(
        _ result: WidgetFetchResult<StatsSummary>,
        current: WidgetSnapshot.Summary?,
        refreshedAt: Date
    ) -> (value: WidgetSnapshot.Summary?, succeeded: Bool) {
        switch result {
        case .success(let stats):
            let candidate = WidgetSnapshot.Summary(
                stats: stats,
                refreshedAt: refreshedAt
            )
            if let current, summaryIsNewer(current, than: candidate) {
                return (current, true)
            }
            return (candidate, true)
        case .failure(let message):
            logFailure(endpoint: "/v1/stats/summary", message: message)
            return (current, false)
        }
    }

    private func resolveLatestMessage(
        _ result: WidgetFetchResult<Message?>,
        current: WidgetSnapshot.LatestMessage?,
        refreshedAt: Date
    ) -> (value: WidgetSnapshot.LatestMessage?, succeeded: Bool) {
        switch result {
        case .success(let message):
            return (
                message.map {
                    WidgetSnapshot.LatestMessage(
                        message: $0,
                        refreshedAt: refreshedAt
                    )
                },
                true
            )
        case .failure(let message):
            logFailure(endpoint: "/v1/messages?limit=1", message: message)
            return (current, false)
        }
    }

    private func resolveComponents(
        _ result: WidgetFetchResult<[SystemComponentCurrentEnvelope]>
    ) -> (value: [SystemComponentCurrentEnvelope]?, succeeded: Bool) {
        switch result {
        case .success(let components):
            return (components, true)
        case .failure(let message):
            logFailure(endpoint: "/v1/system/components/current", message: message)
            return (nil, false)
        }
    }

    private func resolveSystemHealth(
        _ result: WidgetFetchResult<BoothSystemSnapshotEnvelope?>,
        components: [SystemComponentCurrentEnvelope]?,
        current: WidgetSnapshot.SystemHealth?,
        refreshedAt: Date
    ) -> (value: WidgetSnapshot.SystemHealth?, succeeded: Bool) {
        switch result {
        case .success(let envelope):
            if components == nil, let current {
                return (current, true)
            }
            let candidate = envelope.map {
                WidgetSnapshot.SystemHealth(
                    envelope: $0,
                    components: components ?? [],
                    refreshedAt: refreshedAt
                )
            }
            if let current,
               let candidate,
               current.sourceUpdatedAt > candidate.sourceUpdatedAt {
                return (current, true)
            }
            return (candidate, true)
        case .failure(let message):
            logFailure(endpoint: "/v1/system/current", message: message)
            return (current, false)
        }
    }

    private func resolveActivity(
        _ result: WidgetFetchResult<StatsOverview>,
        current: WidgetSnapshot.Activity?,
        refreshedAt: Date
    ) -> (value: WidgetSnapshot.Activity?, succeeded: Bool) {
        switch result {
        case .success(let overview):
            let candidate = WidgetSnapshot.Activity(
                overview: overview,
                refreshedAt: refreshedAt
            )
            let currentRangeEnd = current?.rangeEnd ?? .distantPast
            guard currentRangeEnd > candidate.rangeEnd else {
                return (candidate, true)
            }
            return (current, true)
        case .failure(let message):
            logFailure(endpoint: "/v1/stats/overview?window=24h", message: message)
            return (current, false)
        }
    }

    private func summaryIsNewer(
        _ current: WidgetSnapshot.Summary,
        than candidate: WidgetSnapshot.Summary
    ) -> Bool {
        let currentGeneratedAt = current.sourceGeneratedAt ?? .distantPast
        let candidateGeneratedAt = candidate.sourceGeneratedAt ?? .distantPast
        if currentGeneratedAt != candidateGeneratedAt {
            return currentGeneratedAt > candidateGeneratedAt
        }
        return current.boothUpdatedAt > candidate.boothUpdatedAt
    }
}

private enum WidgetFetchResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(String)
}

private func captureWidgetFetch<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
) async -> WidgetFetchResult<Value> {
    do {
        return .success(try await operation())
    } catch is CancellationError {
        return .failure("cancelled")
    } catch {
        return .failure(error.localizedDescription)
    }
}
