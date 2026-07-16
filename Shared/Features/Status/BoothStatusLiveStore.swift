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
        await refreshFromREST(force: true)
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
                await refreshFromREST(force: isInitialSeed)
            }
            isInitialSeed = false
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                break
            }
        }
    }

    private func refreshFromREST(force: Bool) async {
        if demoMode || config.isDemoMode {
            applyDemoData()
            return
        }
        if !force, connection == .live { return }
        do {
            async let statusResult = client.fetchBoothStatus()
            async let historyResult = client.fetchStatusHistory(limit: 200)
            async let systemResult = client.fetchCurrentSystemEnvelope()
            async let statsResult = client.fetchStatsSummary()
            let (newStatus, newHistory, newSystem, newStats) = try await (
                statusResult,
                historyResult,
                systemResult,
                statsResult
            )
            history = newHistory.items
            apply(status: newStatus)
            systemEnvelope = newSystem
            stats = newStats
            WidgetSnapshotStore.write(WidgetSnapshot(stats: newStats))
            if connection != .live { connection = .polling }
            lastError = nil
        } catch {
            logger.debug("Live status REST refresh failed: \(error.localizedDescription, privacy: .public)")
            if stats == nil && status == nil { connection = .offline }
            lastError = "Couldn't refresh booth status: \(error.localizedDescription)"
        }
    }

    private func apply(_ envelope: WsStatusEnvelope) {
        switch envelope {
        case .status(let status):
            apply(status: status)
        case .system(let envelope):
            systemEnvelope = envelope
            writeWidgetSnapshotIfPossible()
        case .message:
            break
        }
    }

    private func apply(status newStatus: BoothStatus) {
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

    private func mergeIntoHistory(_ newStatus: BoothStatus) {
        history.removeAll { $0.updatedAt == newStatus.updatedAt }
        history.append(newStatus)
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
        WidgetSnapshotStore.write(WidgetSnapshot(stats: DemoData.statsSummary))
    }
}
