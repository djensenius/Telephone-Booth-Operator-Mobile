//
//  BoothStatusLiveStore.swift
//  TelephoneBoothOperatorMobile
//
//  Main-actor store that keeps booth status live via WebSocket with a
//  five-second REST polling fallback.
//

import Foundation
import Observation
import os

@MainActor
@Observable
public final class BoothStatusLiveStore {
    public enum ConnectionState: String, Sendable, Equatable {
        case connecting
        case live
        case polling
        case offline
    }

    public static let shared = BoothStatusLiveStore()
    public static let demo = BoothStatusLiveStore(client: .demo, socket: .demo, demoMode: true)

    public private(set) var status: BoothStatus?
    public private(set) var history: [BoothStatus] = []
    public private(set) var systemEnvelope: BoothSystemSnapshotEnvelope?
    public private(set) var stats: StatsSummary?
    public private(set) var connection: ConnectionState = .offline
    public private(set) var lastError: String?

    /// True only when the `/v1/system/current` request itself failed while we
    /// have no cached snapshot to show. Lets the System tab present its
    /// retry/error state during a system-endpoint outage instead of a
    /// permanent "no snapshot yet". Distinct from the successful-but-empty
    /// case (endpoint reachable, booth simply hasn't reported yet).
    public private(set) var systemUnavailable: Bool = false

    private let client: OperatorClient
    private let socket: StatusSocket
    private let config: AppConfig
    private let demoMode: Bool
    private let pollInterval: Duration = .seconds(5)
    private var socketTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var startCount = 0

    private let logger = Logger(
        subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
        category: "BoothStatusLiveStore"
    )

    public init(
        client: OperatorClient = .shared,
        socket: StatusSocket = .shared,
        config: AppConfig = .shared,
        demoMode: Bool = false
    ) {
        self.client = client
        self.socket = socket
        self.config = config
        self.demoMode = demoMode
    }

    public func start() {
        startCount += 1
        guard startCount == 1 else { return }
        connection = .connecting
        startPollLoop()
        if demoMode || config.isDemoMode {
            connection = .polling
        } else {
            startSocketLoop()
        }
    }

    public func stop() {
        startCount = max(0, startCount - 1)
        guard startCount == 0 else { return }
        socketTask?.cancel()
        socketTask = nil
        pollTask?.cancel()
        pollTask = nil
        connection = .offline
    }

    public func refreshNow() async {
        await refreshFromREST()
    }

    private func startSocketLoop() {
        guard socketTask == nil else { return }
        socketTask = Task { [weak self] in
            await self?.socketLoop()
        }
    }

    private func startPollLoop() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    private func socketLoop() async {
        var backoff: Duration = .seconds(1)
        let maxBackoff: Duration = .seconds(30)
        while !Task.isCancelled {
            if connection != .live { connection = .connecting }
            do {
                for try await envelope in socket.subscribe() {
                    if Task.isCancelled { break }
                    connection = .live
                    lastError = nil
                    backoff = .seconds(1)
                    apply(envelope)
                }
                if !Task.isCancelled { connection = .polling }
            } catch is CancellationError {
                break
            } catch {
                logger.warning("Status socket error: \(error.localizedDescription, privacy: .public)")
                lastError = "Live status disconnected: \(error.localizedDescription)"
                connection = .polling
            }
            guard !Task.isCancelled else { break }
            do {
                try await Task.sleep(for: backoff)
            } catch {
                break
            }
            backoff = min(backoff * 2, maxBackoff)
        }
    }

    private func pollLoop() async {
        var isInitialSeed = true
        while !Task.isCancelled {
            if isInitialSeed || connection != .live {
                await refreshFromREST()
            } else {
                // The live socket owns status/history; keep the summary counts
                // fresh on the cadence because the socket does not carry a
                // StatsSummary.
                await refreshSummary()
                // The socket may not carry system snapshots, so keep polling
                // `/v1/system/current` on the cadence whenever we have none
                // cached — whether the seed failed or simply returned empty
                // before the booth first reported — until one arrives.
                if systemEnvelope == nil { await refreshSystem() }
            }
            isInitialSeed = false
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                break
            }
        }
    }

    private func attempt<Value: Sendable>(_ operation: () async throws -> Value) async -> Value? {
        do {
            return try await operation()
        } catch {
            logger.debug("Live status request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func refreshFromREST() async {
        if demoMode || config.isDemoMode {
            applyDemoData()
            return
        }
        let client = self.client
        async let statusResult = attempt { try await client.fetchBoothStatus() }
        async let historyResult = attempt { try await client.fetchStatusHistory(limit: 200) }
        async let systemResult = attempt { try await client.fetchCurrentSystemEnvelope() }
        async let statsResult = attempt { try await client.fetchStatsSummary() }

        let newStatus = await statusResult
        let newHistory = await historyResult
        let newSystem = await systemResult
        let newStats = await statsResult

        // Apply each successful result independently so one failing endpoint
        // does not discard the others. `apply(status:)` and `mergeHistory`
        // guard against overwriting fresher data delivered by the socket while
        // these requests were in flight.
        if let newHistory { mergeHistory(newHistory.items) }
        if let newStatus { apply(status: newStatus) }
        applySystemResult(newSystem)
        if let newStats { applyStats(newStats) }

        let anySuccess = newStatus != nil || newHistory != nil
            || newSystem != nil || newStats != nil
        if newStatus == nil {
            // Only a failed *current status* request signals degraded status;
            // other successful results above are still applied.
            if status == nil && stats == nil {
                connection = .offline
            } else if connection != .live {
                connection = .polling
            }
            lastError = "Couldn't refresh booth status."
        } else if anySuccess {
            if connection != .live { connection = .polling }
            lastError = nil
        }
    }

    /// Applies the outcome of the `/v1/system/current` REST request. The double
    /// optional distinguishes a thrown error (`.none`) from a successful-but-
    /// empty response (`.some(.none)`) so a system-endpoint outage surfaces an
    /// error state while "booth hasn't reported yet" stays an empty state.
    private func applySystemResult(_ newSystem: BoothSystemSnapshotEnvelope??) {
        switch newSystem {
        case .some(let envelope?):
            // The REST seed races the live socket; don't let an older REST
            // envelope replace a fresher snapshot the socket already applied.
            if let current = systemEnvelope, current.receivedAt >= envelope.receivedAt {
                // Keep the fresher cached snapshot.
            } else {
                systemEnvelope = envelope
                writeWidgetSnapshotIfPossible()
            }
            systemUnavailable = false
        case .some(.none):
            // Endpoint reachable but empty; preserve any snapshot we already
            // hold (e.g. delivered by the socket) rather than erasing it.
            systemUnavailable = false
        case .none:
            // The system request itself failed; only surface an error when we
            // have nothing cached to fall back on.
            systemUnavailable = systemEnvelope == nil
        }
    }

    private func refreshSummary() async {
        if demoMode || config.isDemoMode { return }
        let client = self.client
        if let newStats = await attempt({ try await client.fetchStatsSummary() }) {
            applyStats(newStats)
            lastError = nil
        }
    }

    /// Retry only the `/v1/system/current` endpoint (used on the live-socket
    /// cadence while `systemUnavailable` is set) so the System tab recovers
    /// after an outage without waiting for a full REST reseed.
    private func refreshSystem() async {
        if demoMode || config.isDemoMode { return }
        let client = self.client
        let result = await attempt { try await client.fetchCurrentSystemEnvelope() }
        applySystemResult(result)
    }

    private func apply(_ envelope: WsStatusEnvelope) {
        switch envelope {
        case .status(let status):
            apply(status: status)
        case .system(let envelope):
            systemEnvelope = envelope
            systemUnavailable = false
            writeWidgetSnapshotIfPossible()
        case .message:
            break
        }
    }

    private func apply(status newStatus: BoothStatus) {
        if let current = status, Self.supersedes(current, newStatus) {
            // A fresher status (e.g. from the live socket) already applied while
            // a slower REST response was in flight, so it stays on display —
            // but the report is still a real one, and it may be a delayed
            // transition the history has never seen. The merge drops it if it
            // is only a staler view of a run already held.
            mergeIntoHistory(newStatus)
            return
        }
        status = newStatus
        mergeIntoHistory(newStatus)
        if let currentStats = stats {
            let updatedStats = StatsSummary(
                booth: newStatus,
                messages: currentStats.messages,
                calls: currentStats.calls,
                realtime: currentStats.realtime,
                generatedAt: currentStats.generatedAt
            )
            stats = updatedStats
            WidgetSnapshotStore.write(WidgetSnapshot(stats: updatedStats))
        }
    }

    private func applyStats(_ newStats: StatsSummary) {
        if status == nil { apply(status: newStats.booth) }
        let booth = status ?? newStats.booth
        let merged = StatsSummary(
            booth: booth,
            messages: newStats.messages,
            calls: newStats.calls,
            realtime: newStats.realtime,
            generatedAt: newStats.generatedAt
        )
        stats = merged
        WidgetSnapshotStore.write(WidgetSnapshot(stats: merged))
    }

    private func mergeIntoHistory(_ newStatus: BoothStatus) {
        mergeHistory([newStatus])
    }

    private func mergeHistory(_ items: [BoothStatus]) {
        history = Self.merging(items, into: history)
    }

    /// Whether `held` is a newer view of the same run than `incoming`.
    ///
    /// `updatedAt` decides, except that the operator deliberately leaves it
    /// alone when a delayed report only widens `firstSeenAt` — then the repeat
    /// count is what moved, and a lower count means the report is the older of
    /// the two.
    nonisolated static func supersedes(_ held: BoothStatus, _ incoming: BoothStatus) -> Bool {
        // The booth timestamp decides. An id records when the operator
        // processed a report, not when the booth produced it, so it only
        // breaks ties between reports of the same instant.
        if held.updatedAt != incoming.updatedAt { return held.updatedAt > incoming.updatedAt }
        if let heldId = held.id, let incomingId = incoming.id, heldId != incomingId {
            return heldId > incomingId
        }
        guard held.isSameRun(as: incoming) else { return false }
        return (held.repeatCount ?? 1) > (incoming.repeatCount ?? 1)
    }

    /// Whether `held` is the same stored row as `item` rather than a separate
    /// booth state that happens to look alike.
    nonisolated static func isDuplicate(_ held: BoothStatus, of item: BoothStatus) -> Bool {
        held == item || held.isSameRun(as: item)
    }

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

    /// Cache order: oldest first, by booth timestamp, then by the operator's
    /// insertion order for reports of the same instant — the same order the
    /// operator uses, so a REST page keeps the shape it arrived in.
    private nonisolated static func precedes(_ lhs: BoothStatus, _ rhs: BoothStatus) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        // A row without an id predates them all: only an operator that predates
        // the collapse omits it, and its rows are older than anything a newer
        // operator has served.
        return (lhs.id ?? Int.min) < (rhs.id ?? Int.min)
    }

    /// Splice a REST history page into the cache.
    ///
    /// The page is the operator's own ordered history, so it is authoritative
    /// for the span it covers — merging it entry by entry would append the
    /// whole page again whenever runs share a booth timestamp, since nothing on
    /// the wire tells two identical runs apart. Entries outside the span are
    /// kept, and a run the socket has already delivered in a fresher form keeps
    /// that fresher view.
    private nonisolated static func replacing(
        _ history: [BoothStatus],
        withPage page: [BoothStatus]
    ) -> [BoothStatus] {
        let page = stableOrdered(page)
        guard let oldest = page.first, let newest = page.last else { return history }
        // A run the socket has already advanced keeps that fresher view, and
        // the cached row it came from is then dropped from what is kept — a
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
                    // A pre-collapse operator numbers nothing, so the only test
                    // left is whether the page holds the row at all.
                    return !page.contains { $0 == row || $0.isSameRun(as: row) }
                }
                return id > newestPageId
            }
            .map(\.element)
        return ordered(freshest, unclaimed)
    }

    /// Order a cache without disturbing rows the comparator cannot separate:
    /// two legacy rows can share a timestamp and carry no id, leaving position
    /// as the only thing telling them apart. `sorted(by:)` is not stable.
    private nonisolated static func stableOrdered(_ rows: [BoothStatus]) -> [BoothStatus] {
        rows.enumerated()
            .sorted { lhs, rhs in
                if precedes(lhs.element, rhs.element) { return true }
                if precedes(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Merge two already-ordered caches, keeping that order rather than
    /// re-sorting: position is the only thing separating identical legacy rows.
    private nonisolated static func ordered(
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

    /// Fold a single report (a socket frame) into the cache.
    private nonisolated static func inserting(
        _ item: BoothStatus,
        into history: [BoothStatus]
    ) -> [BoothStatus] {
        var history = history
        if history.contains(where: { $0.isSameRun(as: item) && supersedes($0, item) }) {
            return history
        }
        let insertion = history.firstIndex { precedes(item, $0) } ?? history.count
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

    private func writeWidgetSnapshotIfPossible() {
        if let stats {
            WidgetSnapshotStore.write(WidgetSnapshot(stats: stats))
        }
    }

    private func applyDemoData() {
        let demoNow = Date()
        status = DemoData.liveStatus(now: demoNow)
        history = DemoData.rebasedHistory()
        systemEnvelope = DemoData.systemEnvelope
        let demoStats = DemoData.rebasedStats(to: demoNow)
        stats = demoStats
        connection = .polling
        lastError = nil
        systemUnavailable = false
        WidgetSnapshotStore.write(WidgetSnapshot(stats: demoStats))
    }
}
