//
//  BoothStatusLiveStore+Order.swift
//
//  Ordering the status cache. The booth supplies `updatedAt`, so reports can
//  tie; the operator's row id breaks the tie, and legacy rows that have
//  neither fall back to their position.
//

import Foundation

extension BoothStatusLiveStore {

    /// Cache order: oldest first, by booth timestamp, then by the operator's
    /// insertion order for reports of the same instant.
    nonisolated static func precedes(_ lhs: BoothStatus, _ rhs: BoothStatus) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        // A row without an id predates them all: only an operator that predates
        // the collapse omits it, and its rows are older than anything a newer
        // operator has served.
        return (lhs.id ?? Int.min) < (rhs.id ?? Int.min)
    }

    /// The operator serves history newest first, so flip the page unless it is
    /// demonstrably ascending: legacy rows that tie on their timestamp and
    /// carry no id fall back to position, and a page of nothing but ties — a
    /// burst of same-instant transitions — carries no evidence either way.
    nonisolated static func oldestFirst(_ page: [BoothStatus]) -> [BoothStatus] {
        guard let first = page.first, let last = page.last, precedes(first, last) else {
            return page.reversed()
        }
        return page
    }

    /// Order a cache without disturbing rows the comparator cannot separate;
    /// `sorted(by:)` is not stable.
    nonisolated static func stableOrdered(_ rows: [BoothStatus]) -> [BoothStatus] {
        rows.enumerated()
            .sorted { lhs, rhs in
                if precedes(lhs.element, rhs.element) { return true }
                if precedes(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Merge two ordered caches without re-sorting: position is the only thing
    /// separating identical legacy rows.
    nonisolated static func ordered(
        _ lhs: [BoothStatus],
        _ rhs: [BoothStatus]
    ) -> [BoothStatus] {
        var merged: [BoothStatus] = []
        merged.reserveCapacity(lhs.count + rhs.count)
        var lhsIndex = lhs.startIndex
        var rhsIndex = rhs.startIndex
        while lhsIndex < lhs.endIndex, rhsIndex < rhs.endIndex {
            if precedes(rhs[rhsIndex], lhs[lhsIndex]) {
                merged.append(rhs[rhsIndex])
                rhsIndex += 1
            } else {
                merged.append(lhs[lhsIndex])
                lhsIndex += 1
            }
        }
        merged.append(contentsOf: lhs[lhsIndex...])
        merged.append(contentsOf: rhs[rhsIndex...])
        return merged
    }

    /// The rows either side of where `item` sorts. Without a row id those are
    /// the only ones that can be the same run: a match further off is a shared
    /// booth timestamp with a genuine transition in between.
    nonisolated static func neighbours(of item: BoothStatus, in rows: [BoothStatus]) -> [BoothStatus] {
        let position = rows.firstIndex { precedes(item, $0) } ?? rows.count
        return [position - 1, position].filter(rows.indices.contains).map { rows[$0] }
    }
}
