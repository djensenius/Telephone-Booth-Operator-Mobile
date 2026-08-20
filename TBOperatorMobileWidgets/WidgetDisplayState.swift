//
//  WidgetDisplayState.swift
//  TBOperatorMobileWidgets
//
//  Turns a raw `WidgetSnapshot` (or its absence) into an explicit,
//  per-section display state so every widget can distinguish four
//  distinct situations instead of a single optional:
//
//    * `noSnapshot`      — the host app has never written a snapshot
//                          (signed out, demo reset, first launch).
//    * `missingSection`  — a snapshot exists but this section has not
//                          been populated yet.
//    * `current`         — the section is present and recent.
//    * `stale`           — the section is present but older than its
//                          freshness threshold.
//

import Foundation
import WidgetKit

/// Freshness of a single snapshot section relative to an entry's date.
enum WidgetSectionState<Value> {
    case noSnapshot
    case missingSection
    case current(Value, asOf: Date)
    case stale(Value, asOf: Date)

    var value: Value? {
        switch self {
        case let .current(value, _), let .stale(value, _): return value
        case .noSnapshot, .missingSection: return nil
        }
    }

    var asOf: Date? {
        switch self {
        case let .current(_, asOf), let .stale(_, asOf): return asOf
        case .noSnapshot, .missingSection: return nil
        }
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    /// True when the host has written at least one snapshot but this
    /// particular section has not been filled in yet.
    var isMissingSection: Bool {
        if case .missingSection = self { return true }
        return false
    }
}

extension WidgetSnapshotEntry {
    /// Builds a `WidgetSectionState` for one section of the snapshot.
    /// Gallery/placeholder entries are always treated as current so the
    /// widget picker never renders a "stale" badge over sample data.
    func sectionState<Value>(
        _ value: Value?,
        asOf date: (Value) -> Date,
        staleAfter interval: TimeInterval = WidgetSnapshot.cacheStaleInterval
    ) -> WidgetSectionState<Value> {
        guard snapshot != nil else { return .noSnapshot }
        guard let value else { return .missingSection }
        let asOf = date(value)
        if !isPlaceholder, self.date.timeIntervalSince(asOf) >= interval {
            return .stale(value, asOf: asOf)
        }
        return .current(value, asOf: asOf)
    }

    var summaryState: WidgetSectionState<WidgetSnapshot.Summary> {
        sectionState(snapshot?.summary, asOf: \.refreshedAt)
    }

    var latestMessageState: WidgetSectionState<WidgetSnapshot.LatestMessage> {
        sectionState(snapshot?.latestMessage, asOf: \.refreshedAt)
    }

    var systemHealthState: WidgetSectionState<WidgetSnapshot.SystemHealth> {
        sectionState(snapshot?.systemHealth, asOf: \.refreshedAt)
    }

    var activityState: WidgetSectionState<WidgetSnapshot.Activity> {
        sectionState(snapshot?.activity, asOf: \.refreshedAt)
    }

    /// Upcoming instants at which any present section's freshness changes.
    /// The timeline provider uses the earliest of these to reload exactly
    /// when a section is about to flip stale, rather than always waiting
    /// for the 15-minute fallback. Derived entirely from the entry's own
    /// section timestamps and the shared stale intervals — kept widget-local
    /// so the provider never depends on extending the shared model type.
    func staleTransitionDates(after now: Date) -> [Date] {
        guard !isPlaceholder, let snapshot else { return [] }
        var dates: [Date] = []
        let cache = WidgetSnapshot.cacheStaleInterval
        let source = WidgetSnapshot.sourceStaleInterval
        if let summary = snapshot.summary {
            dates.append(summary.refreshedAt.addingTimeInterval(cache))
        }
        if let latestMessage = snapshot.latestMessage {
            dates.append(latestMessage.refreshedAt.addingTimeInterval(cache))
        }
        if let systemHealth = snapshot.systemHealth {
            dates.append(systemHealth.refreshedAt.addingTimeInterval(cache))
            dates.append(systemHealth.sourceUpdatedAt.addingTimeInterval(source))
        }
        if let activity = snapshot.activity {
            dates.append(activity.refreshedAt.addingTimeInterval(cache))
        }
        return dates.filter { $0 > now }.sorted()
    }
}
