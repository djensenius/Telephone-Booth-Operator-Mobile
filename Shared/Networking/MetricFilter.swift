//
//  MetricFilter.swift
//  TelephoneBoothOperatorMobile
//
//  Mirrors the operator's `MetricFilterSchema` (`/v1/stats/filters`). A saved
//  filter is a per-operator named time selection: either a preset `window`
//  (24h/7d/30d/all) or an explicit `start`/`end` range. `end == nil` with a
//  `start` present means "from start until now".
//

import Foundation

public struct MetricFilter: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let window: StatsWindow?
    public let start: Date?
    public let end: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        name: String,
        window: StatsWindow?,
        start: Date?,
        end: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.window = window
        self.start = start
        self.end = end
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The stats selection this saved filter represents, ready to hand to
    /// `OperatorClient.fetchStatsOverview(selection:)`.
    public var selection: StatsRangeSelection {
        if let window {
            return .window(window)
        }
        return .custom(start: start, endIsNow: end == nil, end: end)
    }
}

/// Request body for `POST`/`PUT /v1/stats/filters`. Send `window` OR
/// `start`/`end`, never both.
public struct MetricFilterInput: Codable, Sendable, Hashable {
    public let name: String
    public let window: StatsWindow?
    public let start: Date?
    public let end: Date?

    public init(name: String, window: StatsWindow?, start: Date?, end: Date?) {
        self.name = name
        self.window = window
        self.start = start
        self.end = end
    }

    /// Build an input from a live selection. Preset windows persist the window;
    /// custom ranges persist explicit timestamps (a "now" end is stored as
    /// `nil`, which the server re-resolves to the current time on read).
    public init(name: String, selection: StatsRangeSelection) {
        self.name = name
        switch selection {
        case .window(let window):
            self.window = window
            start = nil
            end = nil
        case .custom(let start, let endIsNow, let end):
            window = nil
            self.start = start
            self.end = endIsNow ? nil : end
        }
    }
}
