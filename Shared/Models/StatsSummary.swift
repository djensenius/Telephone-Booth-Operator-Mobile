//
//  StatsSummary.swift
//  TelephoneBoothOperatorMobile
//
//  Mirrors the `StatsSummary` schema from the operator OpenAPI spec.
//  This is the primary payload polled by widgets and the dashboard.
//

import Foundation

public struct StatsSummary: Codable, Sendable, Hashable {
    public let booth: BoothStatus
    public let messages: Messages
    public let calls: Calls
    public let realtime: Realtime
    public let generatedAt: Date

    public struct Messages: Codable, Sendable, Hashable {
        public let pending: Int
        public let receivedToday: Int
        public let latestId: UUID?
    }

    public struct Calls: Codable, Sendable, Hashable {
        public let today: Int
        public let inProgress: Int
    }

    public struct Realtime: Codable, Sendable, Hashable {
        public let wsClients: Int
    }

    public init(
        booth: BoothStatus,
        messages: Messages,
        calls: Calls,
        realtime: Realtime,
        generatedAt: Date
    ) {
        self.booth = booth
        self.messages = messages
        self.calls = calls
        self.realtime = realtime
        self.generatedAt = generatedAt
    }
}

/// Placeholder summary used by SwiftUI previews and widget snapshots.
public extension StatsSummary {
    static let placeholder = StatsSummary(
        booth: BoothStatus(
            state: .idle,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        messages: Messages(pending: 2, receivedToday: 7, latestId: nil),
        calls: Calls(today: 4, inProgress: 0),
        realtime: Realtime(wsClients: 1),
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
