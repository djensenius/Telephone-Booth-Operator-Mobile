//
//  WidgetSnapshot.swift
//  TelephoneBoothOperatorMobile
//
//  Compact, widget-friendly view of the latest operator stats. The main
//  app refreshes this snapshot to a shared App Group container after every
//  successful /v1/stats/summary fetch; the widget extension reads it from
//  its own process to render timelines without re-authenticating.
//
//  Keep this struct small and Codable. Bigger payloads bloat widget
//  reload time and aren't shown anyway.
//

import Foundation

public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public let boothState: BoothState
    public let boothUpdatedAt: Date
    public let pendingMessages: Int
    public let receivedToday: Int
    public let callsToday: Int
    public let callsInProgress: Int
    public let wsClients: Int
    public let generatedAt: Date

    public init(
        boothState: BoothState,
        boothUpdatedAt: Date,
        pendingMessages: Int,
        receivedToday: Int,
        callsToday: Int,
        callsInProgress: Int,
        wsClients: Int,
        generatedAt: Date
    ) {
        self.boothState = boothState
        self.boothUpdatedAt = boothUpdatedAt
        self.pendingMessages = pendingMessages
        self.receivedToday = receivedToday
        self.callsToday = callsToday
        self.callsInProgress = callsInProgress
        self.wsClients = wsClients
        self.generatedAt = generatedAt
    }

    public init(stats: StatsSummary) {
        self.init(
            boothState: stats.booth.state,
            boothUpdatedAt: stats.booth.updatedAt,
            pendingMessages: stats.messages.pending,
            receivedToday: stats.messages.receivedToday,
            callsToday: stats.calls.today,
            callsInProgress: stats.calls.inProgress,
            wsClients: stats.realtime.wsClients,
            generatedAt: stats.generatedAt
        )
    }
}

public extension WidgetSnapshot {
    /// Compares only the semantically meaningful fields, ignoring
    /// `generatedAt` which changes on every server response.
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        boothState == other.boothState
            && boothUpdatedAt == other.boothUpdatedAt
            && pendingMessages == other.pendingMessages
            && receivedToday == other.receivedToday
            && callsToday == other.callsToday
            && callsInProgress == other.callsInProgress
            && wsClients == other.wsClients
    }

    /// Placeholder used by widget previews and the loading state.
    static let placeholder = WidgetSnapshot(
        boothState: .idle,
        boothUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        pendingMessages: 2,
        receivedToday: 7,
        callsToday: 4,
        callsInProgress: 0,
        wsClients: 1,
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
