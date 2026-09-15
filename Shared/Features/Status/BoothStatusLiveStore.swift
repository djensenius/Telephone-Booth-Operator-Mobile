//
//  BoothStatusLiveStore.swift
//  TelephoneBoothOperatorMobile
//
//  Main-actor store that keeps booth status live via WebSocket with a
//  five-second REST polling fallback (polling only on watchOS).
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

    public static let shared = BoothStatusLiveStore(lifecycleDefaults: .standard)
    public static let demo = BoothStatusLiveStore(client: .demo, socket: .demo, demoMode: true)

    public private(set) var status: BoothStatus?
    public private(set) var history: [BoothStatus] = []
    public private(set) var systemEnvelope: BoothSystemSnapshotEnvelope?
    public private(set) var componentSources: [SystemComponentCurrentEnvelope] = []
    public private(set) var stats: StatsSummary?
    public internal(set) var callsTodaySessions: [CallSession] = []
    public internal(set) var callsTodayStartedAt: Date?
    public internal(set) var hasLoadedCallsToday = false
    public internal(set) var callsTodayRefreshRevision: UInt = 0
    public private(set) var connection: ConnectionState = .offline
    public private(set) var lastError: String?
    public private(set) var installationState: InstallationState?
    private var lifecycleRevision: UInt = 0
    private var statusError: String?
    private var socketError: String?
    private let lifecycleDefaults: UserDefaults?
    private var lifecycleKey: String

    /// True only when the `/v1/system/current` request itself failed while we
    /// have no cached snapshot to show, so the System tab can show its retry
    /// state during an outage instead of a permanent "no snapshot yet".
    public private(set) var systemUnavailable: Bool = false

    let client: OperatorClient
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
        demoMode: Bool = false,
        lifecycleDefaults: UserDefaults? = nil
    ) {
        self.client = client
        self.socket = socket
        self.config = config
        self.demoMode = demoMode
        self.lifecycleDefaults = lifecycleDefaults
        lifecycleKey = "boothInstallationState:\(config.apiBaseURL.absoluteString)"
        if !demoMode, !config.isDemoMode,
           let rawValue = lifecycleDefaults?.string(forKey: lifecycleKey),
           let cached = InstallationState(rawValue: rawValue) {
            installationState = cached
            status = BoothStatus(
                state: .idle, updatedAt: Date(timeIntervalSince1970: 0),
                installationState: cached, isSynthetic: true
            )
        }
    }

    public func start() {
        startCount += 1
        guard startCount == 1 else { return }
        #if canImport(ActivityKit) && !os(macOS)
        LiveActivityManager.shared.setInstallationState(installationState)
        #endif
        let usesSocket = StatusSocket.supportsLiveConnections && !demoMode && !config.isDemoMode
        connection = usesSocket ? .connecting : .polling
        startPollLoop()
        if usesSocket {
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
                    backoff = .seconds(1)
                    apply(envelope)
                }
                if !Task.isCancelled { connection = .polling }
            } catch is CancellationError {
                break
            } catch {
                logger.warning("Status socket error: \(error.localizedDescription, privacy: .public)")
                socketError = "Live status disconnected: \(error.localizedDescription)"
                lastError = statusError ?? socketError
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
        while !Task.isCancelled {
            // Status frames carry no lifecycle; REST reconciles even when a
            // healthy socket is connected to another API replica.
            await refreshFromREST()
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                break
            }
        }
    }

    func attempt<Value: Sendable>(_ operation: () async throws -> Value) async -> Value? {
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
        let key = "boothInstallationState:\(config.apiBaseURL.absoluteString)"
        if lifecycleKey != key {
            lifecycleKey = key
            installationState = nil
            status = nil
        }
        lifecycleRevision &+= 1
        let revision = lifecycleRevision
        async let statusResult = attempt { try await client.fetchBoothStatus() }
        async let historyResult = attempt { try await client.fetchStatusHistory(limit: 200) }
        async let systemResult = attempt { try await client.fetchCurrentSystemEnvelope() }
        async let componentsResult = attempt { try await client.fetchCurrentSystemComponents() }
        async let summaryResult = fetchSummaryAndSessions()

        let newStatus = await statusResult
        let newHistory = await historyResult
        let newSystem = await systemResult
        let newComponents = await componentsResult
        let summary = await summaryResult

        // Apply each successful result independently so one failing endpoint
        // does not discard the others. `apply(status:)` and `mergeHistory`
        // guard against overwriting fresher data delivered by the socket while
        // these requests were in flight.
        if let newHistory { mergeHistory(newHistory.items) }
        applySystemResult(newSystem)
        if let newComponents { componentSources = newComponents }
        apply(summary, reconcileLifecycle: revision == lifecycleRevision && newStatus == nil)
        if let newStatus, revision == lifecycleRevision {
            apply(status: newStatus, authoritative: true)
        }

        let anySuccess = newStatus != nil || newHistory != nil
            || newSystem != nil || newComponents != nil
            || summary.stats != nil || summary.sessions != nil
        if newStatus == nil {
            // Only a failed *current status* request signals degraded status;
            // other successful results above are still applied.
            if status == nil && stats == nil {
                connection = .offline
            } else if connection != .live {
                connection = .polling
            }
            statusError = "Couldn't refresh booth status."
        } else if anySuccess {
            if connection != .live { connection = .polling }
            statusError = nil
        }
        lastError = statusError ?? socketError
    }

    /// Applies the outcome of the `/v1/system/current` REST request. The double
    /// optional distinguishes a thrown error (`.none`) from a successful-but-
    /// empty response (`.some(.none)`), which stays an empty state.
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

    func apply(_ envelope: WsStatusEnvelope) {
        connection = .live
        socketError = nil
        lastError = statusError
        switch envelope {
        case .status(let status):
            apply(status: status)
        case .system(let envelope):
            systemEnvelope = envelope
            systemUnavailable = false
            writeWidgetSnapshotIfPossible()
        case .message:
            break
        case .installation(let installation):
            lifecycleRevision &+= 1
            apply(status: BoothStatus(
                state: .idle, updatedAt: Date(timeIntervalSince1970: 0),
                installationState: installation.isActive ? .active : .betweenExhibitions,
                isSynthetic: true
            ), authoritative: true)
        case .work, .unknown:
            break
        }
    }

    private func apply(status incoming: BoothStatus, authoritative: Bool = false) {
        if authoritative, let lifecycle = incoming.installationState {
            installationState = lifecycle
            lifecycleDefaults?.set(lifecycle.rawValue, forKey: lifecycleKey)
            #if canImport(ActivityKit) && !os(macOS)
            LiveActivityManager.shared.setInstallationState(lifecycle)
            #endif
        }
        var newStatus = incoming
        newStatus.installationState = installationState
        if !authoritative, installationState == .betweenExhibitions { return }
        if let current = status, current.hasTelemetry, newStatus.hasTelemetry,
           Self.supersedes(current, newStatus) {
            // A fresher status (e.g. from the live socket) already applied while
            // a slower REST response was in flight, so it stays on display —
            // but the report is still a real one, and it may be a delayed
            // transition the history has never seen. The merge drops it if it
            // is only a staler view of a run already held.
            mergeIntoHistory(newStatus)
            newStatus = current
            newStatus.installationState = installationState
        }
        status = newStatus
        mergeIntoHistory(newStatus)
        if let currentStats = stats {
            let updatedStats = StatsSummary(
                booth: newStatus,
                messages: currentStats.messages,
                calls: currentStats.calls,
                interactions: currentStats.interactions,
                actions: currentStats.actions,
                realtime: currentStats.realtime,
                generatedAt: currentStats.generatedAt,
                dayStartedAt: currentStats.dayStartedAt,
                timeZone: currentStats.timeZone
            )
            stats = updatedStats
            writeWidgetSnapshotIfPossible()
        }
    }

    func applyStats(_ newStats: StatsSummary, reconcileLifecycle: Bool = true) {
        if reconcileLifecycle || status == nil {
            apply(status: newStats.booth, authoritative: reconcileLifecycle)
        }
        let booth = status ?? newStats.booth
        let merged = StatsSummary(
            booth: booth,
            messages: newStats.messages,
            calls: newStats.calls,
            interactions: newStats.interactions,
            actions: newStats.actions,
            realtime: newStats.realtime,
            generatedAt: newStats.generatedAt,
            dayStartedAt: newStats.dayStartedAt,
            timeZone: newStats.timeZone
        )
        stats = merged
        writeWidgetSnapshotIfPossible()
    }

    private func mergeIntoHistory(_ newStatus: BoothStatus) {
        guard newStatus.hasTelemetry else { return }
        mergeHistory([newStatus])
    }

    private func mergeHistory(_ items: [BoothStatus]) {
        let reports = items.filter(\.hasTelemetry).map { item in
            var report = item
            report.installationState = nil
            return report
        }
        history = Self.merging(reports, into: history)
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

    private func writeWidgetSnapshotIfPossible() {
        guard !demoMode, !config.isDemoMode, let stats else { return }
        let systemEnvelope = self.systemEnvelope
        let componentSources = self.componentSources
        Task {
            await WidgetRefreshCoordinator.shared.apply(
                stats: stats,
                systemEnvelope: systemEnvelope,
                components: componentSources
            )
        }
    }

    private func applyDemoData() {
        let demoNow = Date()
        status = DemoData.liveStatus(now: demoNow)
        history = DemoData.rebasedHistory()
        systemEnvelope = DemoData.rebasedSystemEnvelope(to: demoNow)
        componentSources = DemoData.rebasedSystemComponentSources(to: demoNow)
        let demoStats = DemoData.rebasedStats(to: demoNow)
        stats = demoStats
        callsTodaySessions = DemoData.rebasedSessions()
        callsTodayStartedAt = demoStats.dayStartedAt
        hasLoadedCallsToday = true
        callsTodayRefreshRevision &+= 1
        connection = .polling
        lastError = nil
        systemUnavailable = false
        writeWidgetSnapshotIfPossible()
    }
}

#if DEBUG
extension BoothStatusLiveStore {
    func applyStatusForTesting(_ newStatus: BoothStatus) {
        apply(status: newStatus)
    }

    func applyRESTStatusForTesting(_ newStatus: BoothStatus) {
        apply(status: newStatus, authoritative: true)
    }
}
#endif
