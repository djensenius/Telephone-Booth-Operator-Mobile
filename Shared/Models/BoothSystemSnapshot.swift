//
//  BoothSystemSnapshot.swift
//  TelephoneBoothOperatorMobile
//
//  Mirrors the operator's `BoothSystemSnapshotSchema` from
//  `packages/shared/src/index.ts`. The canonical wire format groups
//  metrics into sub-objects (`cpu`, `memory`, `disks[]`, `networks[]`,
//  `process`, `audio`, `tailscale`, `throttling`) matching the Rust
//  `booth-hal::SystemSnapshot` struct that the booth client serialises.
//
//  All fields are optional so the schema is forward-compatible with
//  adapters that fill in only a subset of metrics. The snapshot itself
//  does NOT carry a `boothId` or capture timestamp — those live on the
//  envelope, where the server stamps `receivedAt`.
//
//  For convenience, legacy flat-name accessors (`cpuUsageRatio`,
//  `memoryUsedBytes`, `tailscaleConnected`, etc.) are provided as
//  computed shims so callers can read the most common metrics without
//  drilling through optional sub-objects.
//

import Foundation

public struct BoothSystemSnapshot: Codable, Sendable, Equatable {
    public let cpu: CPUStats?
    public let temperatureCelsius: Double?
    public let memory: MemoryStats?
    public let disks: [DiskUsage]?
    public let networks: [NetworkInterface]?
    public let uptimeSeconds: Double?
    public let process: ProcessStats?
    public let audio: AudioStats?
    public let tailscale: TailscaleStats?
    public let throttling: ThrottlingFlags?
    public let runtimeMode: RuntimeMode?
    // Host-identity fields are not in the narrowed operator schema, but
    // adapters routinely include them via `.passthrough()`. Kept optional
    // so absent values decode cleanly.
    public let hostname: String?
    public let osVersion: String?
    public let kernelVersion: String?

    // MARK: - Sub-structs

    public struct CPUStats: Codable, Sendable, Equatable {
        public let usageRatio: Double?
        public let perCoreUsageRatio: [Double]?
        public let physicalCores: Int?
        public let loadAvg1m: Double?
        public let loadAvg5m: Double?
        public let loadAvg15m: Double?

        public init(
            usageRatio: Double? = nil,
            perCoreUsageRatio: [Double]? = nil,
            physicalCores: Int? = nil,
            loadAvg1m: Double? = nil,
            loadAvg5m: Double? = nil,
            loadAvg15m: Double? = nil
        ) {
            self.usageRatio = usageRatio
            self.perCoreUsageRatio = perCoreUsageRatio
            self.physicalCores = physicalCores
            self.loadAvg1m = loadAvg1m
            self.loadAvg5m = loadAvg5m
            self.loadAvg15m = loadAvg15m
        }
    }

    public struct MemoryStats: Codable, Sendable, Equatable {
        public let totalBytes: Double?
        public let usedBytes: Double?
        public let swapTotalBytes: Double?
        public let swapUsedBytes: Double?

        public init(
            totalBytes: Double? = nil,
            usedBytes: Double? = nil,
            swapTotalBytes: Double? = nil,
            swapUsedBytes: Double? = nil
        ) {
            self.totalBytes = totalBytes
            self.usedBytes = usedBytes
            self.swapTotalBytes = swapTotalBytes
            self.swapUsedBytes = swapUsedBytes
        }
    }

    public struct DiskUsage: Codable, Sendable, Equatable, Hashable, Identifiable {
        public let mountPoint: String
        public let filesystem: String?
        public let totalBytes: Double
        public let availableBytes: Double

        public init(
            mountPoint: String,
            filesystem: String? = nil,
            totalBytes: Double,
            availableBytes: Double
        ) {
            self.mountPoint = mountPoint
            self.filesystem = filesystem
            self.totalBytes = totalBytes
            self.availableBytes = availableBytes
        }

        public var id: String { mountPoint }
        /// Legacy lowercase accessor for view code that predates the
        /// schema rename from `mountpoint` to `mountPoint`.
        public var mountpoint: String { mountPoint }
        public var usedBytes: Double { max(0, totalBytes - availableBytes) }
        public var usedRatio: Double? {
            guard totalBytes > 0 else { return nil }
            return usedBytes / totalBytes
        }
    }

    public struct NetworkInterface: Codable, Sendable, Equatable, Hashable, Identifiable {
        public let interface: String
        public let receiveBytesTotal: Double
        public let transmitBytesTotal: Double

        public init(
            interface: String,
            receiveBytesTotal: Double,
            transmitBytesTotal: Double
        ) {
            self.interface = interface
            self.receiveBytesTotal = receiveBytesTotal
            self.transmitBytesTotal = transmitBytesTotal
        }

        public var id: String { interface }
        /// Legacy alias for callers that referenced the interface as `.name`.
        public var name: String { interface }
        /// Legacy alias for callers that referenced `.receivedBytes`.
        public var receivedBytes: Double { receiveBytesTotal }
        /// Legacy alias for callers that referenced `.transmittedBytes`.
        public var transmittedBytes: Double { transmitBytesTotal }
    }

    public struct ProcessStats: Codable, Sendable, Equatable {
        public let residentBytes: Double?
        public let virtualBytes: Double?
        public let openFds: Int?
        public let threads: Int?
        public let uptimeSeconds: Double?

        public init(
            residentBytes: Double? = nil,
            virtualBytes: Double? = nil,
            openFds: Int? = nil,
            threads: Int? = nil,
            uptimeSeconds: Double? = nil
        ) {
            self.residentBytes = residentBytes
            self.virtualBytes = virtualBytes
            self.openFds = openFds
            self.threads = threads
            self.uptimeSeconds = uptimeSeconds
        }
    }

    public struct AudioStats: Codable, Sendable, Equatable {
        public let inputDevice: String?
        public let outputDevice: String?
        public let sampleRateHz: Int?

        public init(
            inputDevice: String? = nil,
            outputDevice: String? = nil,
            sampleRateHz: Int? = nil
        ) {
            self.inputDevice = inputDevice
            self.outputDevice = outputDevice
            self.sampleRateHz = sampleRateHz
        }
    }

    public struct TailscaleStats: Codable, Sendable, Equatable {
        public let connected: Bool?
        public let peerCount: Int?
        public let hostname: String?
        public let exitNode: String?

        public init(
            connected: Bool? = nil,
            peerCount: Int? = nil,
            hostname: String? = nil,
            exitNode: String? = nil
        ) {
            self.connected = connected
            self.peerCount = peerCount
            self.hostname = hostname
            self.exitNode = exitNode
        }
    }

    /// Six boolean Pi throttling flags returned by `vcgencmd get_throttled`.
    /// Adapters that can't read these (non-Pi hosts) omit the whole object.
    public struct ThrottlingFlags: Codable, Sendable, Equatable {
        public let undervoltage: Bool?
        public let armFreqCapped: Bool?
        public let throttled: Bool?
        public let softTempLimit: Bool?
        public let undervoltageOccurred: Bool?
        public let throttledOccurred: Bool?

        public init(
            undervoltage: Bool? = nil,
            armFreqCapped: Bool? = nil,
            throttled: Bool? = nil,
            softTempLimit: Bool? = nil,
            undervoltageOccurred: Bool? = nil,
            throttledOccurred: Bool? = nil
        ) {
            self.undervoltage = undervoltage
            self.armFreqCapped = armFreqCapped
            self.throttled = throttled
            self.softTempLimit = softTempLimit
            self.undervoltageOccurred = undervoltageOccurred
            self.throttledOccurred = throttledOccurred
        }

        /// Collects the asserted (true) flags into a stable-ordered array of
        /// their canonical names. Used to drive the "Throttling" UI tile,
        /// which shows a count + optional list of names.
        public var assertedFlagNames: [String] {
            var result: [String] = []
            if undervoltage == true { result.append("undervoltage") }
            if armFreqCapped == true { result.append("armFreqCapped") }
            if throttled == true { result.append("throttled") }
            if softTempLimit == true { result.append("softTempLimit") }
            if undervoltageOccurred == true { result.append("undervoltageOccurred") }
            if throttledOccurred == true { result.append("throttledOccurred") }
            return result
        }
    }

    public init(
        cpu: CPUStats? = nil,
        temperatureCelsius: Double? = nil,
        memory: MemoryStats? = nil,
        disks: [DiskUsage]? = nil,
        networks: [NetworkInterface]? = nil,
        uptimeSeconds: Double? = nil,
        process: ProcessStats? = nil,
        audio: AudioStats? = nil,
        tailscale: TailscaleStats? = nil,
        throttling: ThrottlingFlags? = nil,
        runtimeMode: RuntimeMode? = nil,
        hostname: String? = nil,
        osVersion: String? = nil,
        kernelVersion: String? = nil
    ) {
        self.cpu = cpu
        self.temperatureCelsius = temperatureCelsius
        self.memory = memory
        self.disks = disks
        self.networks = networks
        self.uptimeSeconds = uptimeSeconds
        self.process = process
        self.audio = audio
        self.tailscale = tailscale
        self.throttling = throttling
        self.runtimeMode = runtimeMode
        self.hostname = hostname
        self.osVersion = osVersion
        self.kernelVersion = kernelVersion
    }

    // MARK: - Legacy flat-name accessors
    //
    // The pre-PR-71 schema used flat field names (`cpuUsageRatio`,
    // `memoryUsedBytes`, …) and several call sites still read those.
    // These computed properties keep view code terse without forcing
    // every caller to drill through the new nested sub-objects.

    public var cpuTemperatureCelsius: Double? { temperatureCelsius }
    public var cpuUsageRatio: Double? { cpu?.usageRatio }
    public var cpuUsageRatioPerCore: [Double]? { cpu?.perCoreUsageRatio }
    public var loadAverage1m: Double? { cpu?.loadAvg1m }
    public var loadAverage5m: Double? { cpu?.loadAvg5m }
    public var loadAverage15m: Double? { cpu?.loadAvg15m }
    public var memoryUsedBytes: Double? { memory?.usedBytes }
    public var memoryTotalBytes: Double? { memory?.totalBytes }
    public var swapUsedBytes: Double? { memory?.swapUsedBytes }
    public var swapTotalBytes: Double? { memory?.swapTotalBytes }
    public var tailscaleConnected: Bool? { tailscale?.connected }
    public var tailscaleHostname: String? { tailscale?.hostname }
    public var audioInputDevice: String? { audio?.inputDevice }
    public var audioOutputDevice: String? { audio?.outputDevice }
    /// Per-channel level readings are not currently produced by the booth
    /// client, but the accessor is retained so optional-chained call sites
    /// continue to compile and simply render dashes.
    public var audioInputDbfs: Double? { nil }
    public var audioOutputDbfs: Double? { nil }
    /// Alias preserving the pre-rename `networkInterfaces` array name.
    public var networkInterfaces: [NetworkInterface]? { networks }
    /// Names of currently-asserted Pi throttling flags. Returns nil when no
    /// throttling sub-object was reported so absent-data and zero-asserted
    /// states render differently.
    public var throttlingFlags: [String]? {
        guard let throttling else { return nil }
        return throttling.assertedFlagNames
    }

    public var memoryUsedRatio: Double? {
        guard let used = memory?.usedBytes,
              let total = memory?.totalBytes,
              total > 0 else {
            return nil
        }
        return used / total
    }

    public var swapUsedRatio: Double? {
        guard let used = memory?.swapUsedBytes,
              let total = memory?.swapTotalBytes,
              total > 0 else {
            return nil
        }
        return used / total
    }

    /// Inferred CPU core count: prefers the explicit `physicalCores`
    /// field, falls back to the per-core usage array length.
    public var cpuCoreCount: Int? {
        if let physical = cpu?.physicalCores, physical > 0 { return physical }
        if let cores = cpu?.perCoreUsageRatio, !cores.isEmpty { return cores.count }
        return nil
    }
}

/// Envelope returned by `GET /v1/system/current?boothId=...` and the
/// items inside `GET /v1/system/current` (list form). Matches the
/// operator's `BoothSystemSnapshotEnvelopeSchema`.
public struct BoothSystemSnapshotEnvelope: Codable, Sendable, Equatable, Identifiable {
    public let boothId: String
    public let snapshot: BoothSystemSnapshot
    public let receivedAt: Date
    public let version: String?

    public init(boothId: String, snapshot: BoothSystemSnapshot, receivedAt: Date, version: String? = nil) {
        self.boothId = boothId
        self.snapshot = snapshot
        self.receivedAt = receivedAt
        self.version = version
    }

    public var id: String { boothId }
}

/// `GET /v1/system/current` (no `boothId` filter) returns `{ items: [...] }`.
public struct BoothSystemSnapshotList: Codable, Sendable, Equatable {
    public let items: [BoothSystemSnapshotEnvelope]

    public init(items: [BoothSystemSnapshotEnvelope]) {
        self.items = items
    }
}

public struct StatusHistory: Codable, Sendable, Equatable {
    public let items: [BoothStatus]

    public init(items: [BoothStatus]) {
        self.items = items
    }
}
