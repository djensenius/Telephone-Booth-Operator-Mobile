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
        /// Messages awaiting operator moderation (server counts "received" +
        /// "pending"). Drives the app-icon / tab badge. Optional so snapshots
        /// from older operator builds (which omit it) still decode.
        public let awaitingModeration: Int?
        public let receivedToday: Int
        public let latestId: UUID?

        public init(
            pending: Int,
            awaitingModeration: Int? = nil,
            receivedToday: Int,
            latestId: UUID?
        ) {
            self.pending = pending
            self.awaitingModeration = awaitingModeration
            self.receivedToday = receivedToday
            self.latestId = latestId
        }

        /// The badge value: prefer the explicit awaiting-moderation count,
        /// falling back to `pending` for older operator responses.
        public var badgeCount: Int { awaitingModeration ?? pending }
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
        messages: Messages(pending: 2, awaitingModeration: 2, receivedToday: 7, latestId: nil),
        calls: Calls(today: 4, inProgress: 0),
        realtime: Realtime(wsClients: 1),
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
