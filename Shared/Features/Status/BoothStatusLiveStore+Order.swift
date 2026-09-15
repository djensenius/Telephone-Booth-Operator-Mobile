//
//  BoothStatusLiveStore+Order.swift
//
//  Ordering the status cache. The booth supplies `updatedAt`, so reports can
//  tie; the operator's row id breaks the tie, and legacy rows that have
//  neither fall back to their position.
//

import Foundation

struct CallsTodayRefresh: Sendable {
    let stats: StatsSummary?
    let sessions: [CallSession]?
    let dayStartedAt: Date
}

extension BoothStatusLiveStore {

    nonisolated static func merging(
        _ items: [BoothStatus],
        into history: [BoothStatus],
        limit: Int = 200
    ) -> [BoothStatus] {
        var history = stableOrdered(history)
        if items.count > 1 {
            history = replacing(history, withPage: items)
        } else if let item = items.first {
            history = inserting(item, into: history)
        }
        if history.count > limit {
            history.removeFirst(history.count - limit)
        }
        return history
    }

    /// Splice a REST history page into the cache. It is the operator's own
    /// ordered history, so it is authoritative
    /// for the span it covers — merging it entry by entry would append the
    /// whole page again whenever runs share a booth timestamp. Entries outside
    /// the span are kept, and a run the socket already has fresher stays so.
    private nonisolated static func replacing(
        _ history: [BoothStatus],
        withPage page: [BoothStatus]
    ) -> [BoothStatus] {
        let page = stableOrdered(oldestFirst(page))
        guard let oldest = page.first, let newest = page.last else { return history }
        // A run the socket has already advanced keeps that fresher view, and
        // the cached row it came from is dropped from what is kept — a
        // heartbeat can push it past the page's newest report, where it would
        // otherwise be held twice.
        var reused: Set<Int> = []
        let freshest = page.map { item -> BoothStatus in
            guard let index = history.firstIndex(where: {
                $0.isSameRun(as: item) && supersedes($0, item)
            }) else { return item }
            reused.insert(index)
            return history[index]
        }
        // Cached rows the page does not speak for: those ordered outside it,
        // and those the operator inserted after generating it — a report
        // delayed past the page's oldest entry is broadcast with a row id newer
        // than anything in the page even though its booth timestamp falls
        // inside the span.
        let newestPageId = page.compactMap(\.id).max() ?? Int.min
        let unclaimed = history.enumerated()
            .filter { offset, row in
                guard !reused.contains(offset) else { return false }
                if precedes(row, oldest) || precedes(newest, row) { return true }
                guard let id = row.id else {
                    // A pre-collapse operator numbers nothing: the row is the
                    // page's own only if the page holds it outright, or holds a
                    // matching run where the row itself would sort.
                    if page.contains(where: { $0 == row }) { return false }
                    return !neighbours(of: row, in: page).contains { $0.isSameRun(as: row) }
                }
                return id > newestPageId
            }
            .map(\.element)
        return ordered(freshest, unclaimed)
    }

    /// Fold a single report (a socket frame) into the cache.
    private nonisolated static func inserting(
        _ item: BoothStatus,
        into history: [BoothStatus]
    ) -> [BoothStatus] {
        var history = history
        // An identified row is the same run wherever it sits, but matching an
        // id-less one by its window has to stay local: a short run can share a
        // millisecond with the identical runs either side of it.
        let insertion = history.firstIndex { precedes(item, $0) } ?? history.count
        let held = item.id == nil ? neighbours(of: item, in: history) : history
        if held.contains(where: { $0.isSameRun(as: item) && supersedes($0, item) }) {
            return history
        }
        history.insert(item, at: insertion)
        // Collapse only the entries sitting next to the inserted one. A run can
        // be held several times over (a socket frame plus a REST refresh), but
        // anything separated by a differing status is a distinct row: the booth
        // supplies `updatedAt`, so a short run can share a millisecond with the
        // identical runs around it, and removing those by value would erase a
        // genuine transition.
        var lower = insertion
        while lower > 0, isDuplicate(history[lower - 1], of: item) { lower -= 1 }
        var upper = insertion
        while upper + 1 < history.count, isDuplicate(history[upper + 1], of: item) { upper += 1 }
        if upper > insertion { history.removeSubrange((insertion + 1)...upper) }
        if lower < insertion { history.removeSubrange(lower..<insertion) }
        return history
    }

    /// Booth timestamps order reports; row ids break ties and repeat counts
    /// distinguish a delayed extension of the same collapsed run.
    nonisolated static func supersedes(_ held: BoothStatus, _ incoming: BoothStatus) -> Bool {
        if held.updatedAt != incoming.updatedAt { return held.updatedAt > incoming.updatedAt }
        if let heldId = held.id, let incomingId = incoming.id, heldId != incomingId {
            return heldId > incomingId
        }
        guard held.isSameRun(as: incoming) else { return false }
        return (held.repeatCount ?? 1) > (incoming.repeatCount ?? 1)
    }

    nonisolated static func isDuplicate(_ held: BoothStatus, of item: BoothStatus) -> Bool {
        held == item || held.isSameRun(as: item)
    }

    func fetchSummaryAndSessions() async -> CallsTodayRefresh {
        let client = self.client
        let localDayStartedAt = Calendar.current.startOfDay(for: Date())
        prepareCallsToday(for: localDayStartedAt)
        let knownSessionIDs = Set(callsTodaySessions.map(\.id))
        async let statsResult = attempt { try await client.fetchStatsSummary() }
        async let sessionsResult = attempt {
            try await client.fetchSessions(
                startedOnOrAfter: localDayStartedAt,
                knownSessionIDs: knownSessionIDs
            )
        }

        let newStats = await statsResult
        var newSessions = await sessionsResult
        let dayStartedAt = newStats?.dayStartedAt ?? localDayStartedAt
        if dayStartedAt != localDayStartedAt {
            prepareCallsToday(for: dayStartedAt)
            newSessions = await attempt {
                try await client.fetchSessions(startedOnOrAfter: dayStartedAt)
            }
        }
        return CallsTodayRefresh(
            stats: newStats,
            sessions: newSessions,
            dayStartedAt: dayStartedAt
        )
    }

    func prepareCallsToday(for dayStartedAt: Date) {
        guard callsTodayStartedAt != dayStartedAt else { return }
        callsTodayStartedAt = dayStartedAt
        callsTodaySessions = []
        hasLoadedCallsToday = false
    }

    func apply(_ summary: CallsTodayRefresh, reconcileLifecycle: Bool = true) {
        prepareCallsToday(for: summary.dayStartedAt)
        if let newStats = summary.stats {
            applyStats(newStats, reconcileLifecycle: reconcileLifecycle)
        }
        if let sessions = summary.sessions {
            var sessionsByID = [String: CallSession]()
            for session in callsTodaySessions + sessions {
                sessionsByID[session.id] = session
            }
            callsTodaySessions = sessionsByID.values
                .filter { $0.startedAt >= summary.dayStartedAt }
                .sorted {
                    if $0.startedAt == $1.startedAt {
                        return $0.id < $1.id
                    }
                    return $0.startedAt < $1.startedAt
                }
            hasLoadedCallsToday = true
                callsTodayRefreshRevision &+= 1
        }
    }

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
