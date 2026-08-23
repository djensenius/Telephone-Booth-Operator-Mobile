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
    public let interactions: Calls?
    public let actions: Actions?
    public let realtime: Realtime
    public let generatedAt: Date
    public let dayStartedAt: Date?
    public let timeZone: String?

    public struct Messages: Codable, Sendable, Hashable {
        public let pending: Int
        /// Messages awaiting operator moderation (server counts "received" +
        /// "pending"). Drives the app-icon / tab badge. Optional so snapshots
        /// from older operator builds (which omit it) still decode.
        public let awaitingModeration: Int?
        public let receivedToday: Int
        /// Messages created today that remain available to the booth. Optional
        /// for compatibility with older operator builds.
        public let availableToday: Int?
        public let latestId: UUID?

        public init(
            pending: Int,
            awaitingModeration: Int? = nil,
            receivedToday: Int,
            availableToday: Int? = nil,
            latestId: UUID?
        ) {
            self.pending = pending
            self.awaitingModeration = awaitingModeration
            self.receivedToday = receivedToday
            self.availableToday = availableToday
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

    public struct Actions: Codable, Sendable, Hashable {
        public let messagePlaybackStarts: Int

        public init(messagePlaybackStarts: Int) {
            self.messagePlaybackStarts = messagePlaybackStarts
        }
    }

    public struct Realtime: Codable, Sendable, Hashable {
        public let wsClients: Int
    }

    public init(
        booth: BoothStatus,
        messages: Messages,
        calls: Calls,
        interactions: Calls? = nil,
        actions: Actions? = nil,
        realtime: Realtime,
        generatedAt: Date,
        dayStartedAt: Date? = nil,
        timeZone: String? = nil
    ) {
        self.booth = booth
        self.messages = messages
        self.calls = calls
        self.interactions = interactions
        self.actions = actions
        self.realtime = realtime
        self.generatedAt = generatedAt
        self.dayStartedAt = dayStartedAt
        self.timeZone = timeZone
    }
}

/// Placeholder summary used by SwiftUI previews and widget snapshots.
public extension StatsSummary {
    var interactionCounts: Calls { interactions ?? calls }
    var interactionsToday: Int { interactionCounts.today }
    var interactionsInProgress: Int { interactionCounts.inProgress }

    static let placeholder = StatsSummary(
        booth: BoothStatus(
            state: .idle,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        messages: Messages(
            pending: 2,
            awaitingModeration: 2,
            receivedToday: 7,
            availableToday: 6,
            latestId: nil
        ),
        calls: Calls(today: 4, inProgress: 0),
        interactions: Calls(today: 4, inProgress: 0),
        actions: Actions(messagePlaybackStarts: 3),
        realtime: Realtime(wsClients: 1),
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        dayStartedAt: nil,
        timeZone: nil
    )
}
