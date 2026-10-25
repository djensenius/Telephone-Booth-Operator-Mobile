//
//  WidgetSnapshot+Merging.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

extension WidgetSnapshot {
    /// Host and extension may finish independent requests in either order.
    /// Preserve the freshest independently dated section, not just the newest file.
    func mergingNewerSections(from other: WidgetSnapshot?) -> WidgetSnapshot {
        guard let other else { return self }
        let otherMessageIsNewer = (other.latestMessageRefreshedAt ?? .distantPast)
            > (latestMessageRefreshedAt ?? .distantPast)
        let otherHealthIsNewer = healthFromOtherIsNewer(other)
        let healthObservedAt = [systemHealthRefreshedAt, other.systemHealthRefreshedAt].compactMap { $0 }.max()
        var health = otherHealthIsNewer ? other.systemHealth : systemHealth
        if let selected = health, let first = systemHealth, let second = other.systemHealth {
            health = selected.mergingRouter(from: otherHealthIsNewer ? first : second)
        }
        return WidgetSnapshot(
            summary: mergedSummary(with: other.summary),
            latestMessage: otherMessageIsNewer ? other.latestMessage : latestMessage,
            latestMessageRefreshedAt: otherMessageIsNewer ? other.latestMessageRefreshedAt : latestMessageRefreshedAt,
            systemHealth: Self.updatingHealth(health, observedAt: healthObservedAt),
            systemHealthRefreshedAt: healthObservedAt,
            activity: Self.newer(activity, other.activity, source: \.rangeEnd, date: \.refreshedAt),
            writtenAt: max(writtenAt, other.writtenAt)
        )
    }

    private func healthFromOtherIsNewer(_ other: WidgetSnapshot) -> Bool {
        if let first = systemHealth, let second = other.systemHealth {
            if first.sourceUpdatedAt != second.sourceUpdatedAt { return second.sourceUpdatedAt > first.sourceUpdatedAt }
            let firstEvaluation = first.evaluatedAt ?? first.refreshedAt
            let secondEvaluation = second.evaluatedAt ?? second.refreshedAt
            if firstEvaluation != secondEvaluation { return secondEvaluation > firstEvaluation }
        }
        return (other.systemHealthRefreshedAt ?? .distantPast) > (systemHealthRefreshedAt ?? .distantPast)
    }

    private static func updatingHealth(_ health: SystemHealth?, observedAt: Date?) -> SystemHealth? {
        guard let health, let observedAt, observedAt > health.refreshedAt else { return health }
        return SystemHealth(
            boothId: health.boothId, severity: health.severity,
            cpuTemperatureCelsius: health.cpuTemperatureCelsius, memoryUsedRatio: health.memoryUsedRatio,
            routerTemperatureCelsius: health.routerTemperatureCelsius, tailscaleConnected: health.tailscaleConnected,
            sourceUpdatedAt: health.sourceUpdatedAt, refreshedAt: observedAt,
            evaluatedAt: health.evaluatedAt ?? health.refreshedAt,
            routerSourceUpdatedAt: health.routerSourceUpdatedAt,
            routerObservedAt: health.routerObservedAt, boothSeverity: health.boothSeverity
        )
    }

    private func mergedSummary(with other: Summary?) -> Summary? {
        guard let summary else { return other }
        guard let other else { return summary }
        let status = Self.newerStatus(summary, other)
        let firstCountsDate = summary.countsSourceGeneratedAt ?? summary.sourceGeneratedAt ?? summary.refreshedAt
        let otherCountsDate = other.countsSourceGeneratedAt ?? other.sourceGeneratedAt ?? other.refreshedAt
        let counts = otherCountsDate > firstCountsDate ? other : summary
        return Summary(
            boothState: status.boothState, boothUpdatedAt: status.boothUpdatedAt,
            pendingMessages: counts.pendingMessages, receivedToday: counts.receivedToday,
            interactionsToday: counts.interactionsToday, interactionsInProgress: counts.interactionsInProgress,
            wsClients: counts.wsClients, runtimeMode: status.runtimeMode,
            sourceGeneratedAt: status.sourceGeneratedAt, refreshedAt: status.refreshedAt,
            installationState: status.installationState, isSynthetic: status.isSynthetic,
            countsSourceGeneratedAt: max(firstCountsDate, otherCountsDate)
        )
    }

    private static func newerStatus(_ first: Summary, _ second: Summary) -> Summary {
        // Lifecycle belongs to the observation, not a synthetic epoch heartbeat.
        if first.installationState != second.installationState || first.isSynthetic != second.isSynthetic {
            return second.refreshedAt > first.refreshedAt ? second : first
        }
        if first.boothUpdatedAt != second.boothUpdatedAt {
            return second.boothUpdatedAt > first.boothUpdatedAt ? second : first
        }
        let firstSource = first.sourceGeneratedAt ?? .distantPast
        let secondSource = second.sourceGeneratedAt ?? .distantPast
        if firstSource != secondSource { return secondSource > firstSource ? second : first }
        return second.refreshedAt > first.refreshedAt ? second : first
    }

    private static func newer<Value>(
        _ first: Value?, _ second: Value?, source: KeyPath<Value, Date>, date: KeyPath<Value, Date>
    ) -> Value? {
        guard let first else { return second }
        guard let second else { return first }
        if second[keyPath: source] != first[keyPath: source] {
            return second[keyPath: source] > first[keyPath: source] ? second : first
        }
        return second[keyPath: date] > first[keyPath: date] ? second : first
    }
}
