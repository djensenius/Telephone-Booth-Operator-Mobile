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
        return WidgetSnapshot(
            summary: mergedSummary(with: other.summary),
            latestMessage: otherMessageIsNewer ? other.latestMessage : latestMessage,
            latestMessageRefreshedAt: otherMessageIsNewer ? other.latestMessageRefreshedAt : latestMessageRefreshedAt,
            systemHealth: Self.newer(systemHealth, other.systemHealth, source: \.sourceUpdatedAt, date: \.refreshedAt),
            activity: Self.newer(activity, other.activity, source: \.rangeEnd, date: \.refreshedAt),
            writtenAt: max(writtenAt, other.writtenAt)
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
