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
        if let current = status, current.updatedAt > newStatus.updatedAt {
            // A fresher status (e.g. from the live socket) already applied while
            // a slower REST response was in flight; ignore the stale update.
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
        for item in items {
            history.removeAll { $0.updatedAt == item.updatedAt }
            history.append(item)
        }
        history.sort { $0.updatedAt < $1.updatedAt }
        if history.count > 200 {
            history.removeFirst(history.count - 200)
        }
    }

    private func writeWidgetSnapshotIfPossible() {
        if let stats {
            WidgetSnapshotStore.write(WidgetSnapshot(stats: stats))
        }
    }

    private func applyDemoData() {
        status = DemoData.boothStatus
        history = DemoData.statusHistory
        systemEnvelope = DemoData.systemEnvelope
        stats = DemoData.statsSummary
        connection = .polling
        lastError = nil
        systemUnavailable = false
        WidgetSnapshotStore.write(WidgetSnapshot(stats: DemoData.statsSummary))
    }
}
