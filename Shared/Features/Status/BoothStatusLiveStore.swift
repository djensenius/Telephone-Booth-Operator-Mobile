//
//  BoothStatusLiveStore.swift
//  TelephoneBoothOperatorMobile
//
//  Main-actor store that keeps booth status live via WebSocket with a
//  five-second REST lifecycle reconciliation (polling only on watchOS).
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
        synchronizeAPIBase()
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
        var isInitialSeed = true
        while !Task.isCancelled {
            // Status frames carry no lifecycle; REST reconciles even when a
            // healthy socket is connected to another API replica.
            await refreshFromREST(fullRefresh: isInitialSeed || connection != .live)
            isInitialSeed = false
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

    private func refreshFromREST(fullRefresh: Bool = true) async {
        if demoMode || config.isDemoMode {
            applyDemoData()
            return
        }
        let changedAPI = synchronizeAPIBase()
        let fullRefresh = fullRefresh || changedAPI
        let client = self.client
        let cachedSystem = systemEnvelope
        let requestKey = lifecycleKey
        lifecycleRevision &+= 1
        let revision = lifecycleRevision
        async let statusResult = attempt { try await client.fetchBoothStatus() }
        async let historyResult: StatusHistory? = fullRefresh
            ? attempt { try await client.fetchStatusHistory(limit: 200) } : nil
        async let systemResult: BoothSystemSnapshotEnvelope?? = fullRefresh || cachedSystem == nil
            ? attempt { try await client.fetchCurrentSystemEnvelope() } : .some(cachedSystem)
        async let componentsResult = attempt { try await client.fetchCurrentSystemComponents() }
        async let summaryResult = fetchSummaryAndSessions()

        let newStatus = await statusResult
        let newHistory = await historyResult
        let newSystem = await systemResult
        let newComponents = await componentsResult
        let summary = await summaryResult
        guard requestKey == lifecycleKey,
              requestKey == "boothInstallationState:\(config.apiBaseURL.absoluteString)" else { return }

        if let newHistory { mergeHistory(newHistory.items) }
        applySystemResult(newSystem)
        if let newComponents { componentSources = newComponents }
        apply(summary, reconcileLifecycle: revision == lifecycleRevision && newStatus == nil)
        if let newStatus, revision == lifecycleRevision {
            apply(status: newStatus, authoritative: true)
        }

        if newStatus == nil {
            if status == nil && stats == nil {
                connection = .offline
            } else if connection != .live {
                connection = .polling
            }
            statusError = "Couldn't refresh booth status."
        } else {
            if connection != .live { connection = .polling }
            statusError = nil
        }
        lastError = statusError ?? socketError
    }

    @discardableResult
    private func synchronizeAPIBase() -> Bool {
        let key = "boothInstallationState:\(config.apiBaseURL.absoluteString)"
        guard lifecycleKey != key else { return false }
        lifecycleKey = key
        installationState = lifecycleDefaults?.string(forKey: key).flatMap(InstallationState.init(rawValue:))
        status = installationState.map {
            BoothStatus(state: .idle, updatedAt: Date(timeIntervalSince1970: 0),
                        installationState: $0, isSynthetic: true)
        }
        stats = nil
        history = []
        systemEnvelope = nil
        componentSources = []
        systemUnavailable = false
        callsTodaySessions = []
        callsTodayStartedAt = nil
        hasLoadedCallsToday = false
        statusError = nil
        socketError = nil
        lastError = nil
        lifecycleRevision &+= 1
        #if canImport(ActivityKit) && !os(macOS)
        LiveActivityManager.shared.resetInstallationState(installationState)
        #endif
        socketTask?.cancel()
        socketTask = nil
        if startCount > 0, !demoMode, !config.isDemoMode, StatusSocket.supportsLiveConnections {
            startSocketLoop()
        }
        return true
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

    private func writeWidgetSnapshotIfPossible() {
        guard !demoMode, !config.isDemoMode, let stats else { return }
        let systemEnvelope = self.systemEnvelope
        let componentSources = self.componentSources
        let apiRevision = WidgetRefreshCoordinator.currentAPIRevision
        Task {
            await WidgetRefreshCoordinator.shared.apply(
                stats: stats,
                systemEnvelope: systemEnvelope,
                components: componentSources,
                apiRevision: apiRevision
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
