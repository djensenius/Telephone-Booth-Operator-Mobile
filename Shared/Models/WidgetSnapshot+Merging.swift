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
        let health = otherHealthIsNewer ? other.systemHealth : systemHealth
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
            evaluatedAt: health.evaluatedAt ?? health.refreshedAt
        )
    }

    private func mergedSummary(with other: Summary?) -> Summary? {
        guard let summary else { return other }
        guard let other else { return summary }
        // Lifecycle belongs to the observation, not a synthetic epoch heartbeat.
        if summary.installationState != other.installationState || summary.isSynthetic != other.isSynthetic {
            return other.refreshedAt > summary.refreshedAt ? other : summary
        }
        let firstSource = summary.sourceGeneratedAt ?? summary.boothUpdatedAt
        let secondSource = other.sourceGeneratedAt ?? other.boothUpdatedAt
        if firstSource != secondSource { return secondSource > firstSource ? other : summary }
        if summary.boothUpdatedAt != other.boothUpdatedAt {
            return other.boothUpdatedAt > summary.boothUpdatedAt ? other : summary
        }
        return other.refreshedAt > summary.refreshedAt ? other : summary
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
