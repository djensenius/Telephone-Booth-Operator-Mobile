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
            summary: Self.newer(summary, other.summary, date: \.refreshedAt),
            latestMessage: otherMessageIsNewer ? other.latestMessage : latestMessage,
            latestMessageRefreshedAt: otherMessageIsNewer ? other.latestMessageRefreshedAt : latestMessageRefreshedAt,
            systemHealth: Self.newer(systemHealth, other.systemHealth, date: \.refreshedAt),
            activity: Self.newer(activity, other.activity, date: \.refreshedAt),
            writtenAt: max(writtenAt, other.writtenAt)
        )
    }

    private static func newer<Value>(_ first: Value?, _ second: Value?, date: KeyPath<Value, Date>) -> Value? {
        guard let first else { return second }
        guard let second else { return first }
        return second[keyPath: date] > first[keyPath: date] ? second : first
    }
}
