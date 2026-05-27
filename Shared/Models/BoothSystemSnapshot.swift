//
//  BoothSystemSnapshot.swift
//  TelephoneBoothOperatorMobile
//
//  Mirrors the operator's `BoothSystemSnapshotSchema` from
//  `packages/shared/src/index.ts`. Every host metric field is nullable +
//  optional so the schema is forward-compatible with new metrics. The
//  operator's `openapi.yaml` is currently a stale subset of this — the
//  Zod schema is the source of truth.
//

import Foundation

public struct BoothSystemSnapshot: Codable, Sendable, Equatable {
    public let boothId: String
    public let capturedAt: Date
    public let uptimeSeconds: Double?
    public let hostname: String?
    public let osVersion: String?
    public let kernelVersion: String?
    public let cpuTemperatureCelsius: Double?
    public let cpuUsageRatio: Double?
    public let cpuUsageRatioPerCore: [Double]?
    public let loadAverage1m: Double?
    public let loadAverage5m: Double?
    public let loadAverage15m: Double?
    public let memoryUsedBytes: Double?
    public let memoryTotalBytes: Double?
    public let swapUsedBytes: Double?
    public let swapTotalBytes: Double?
    public let disks: [DiskUsage]?
    public let networkInterfaces: [NetworkInterface]?
    public let audioInputDevice: String?
    public let audioOutputDevice: String?
    public let audioInputDbfs: Double?
    public let audioOutputDbfs: Double?
    public let tailscaleConnected: Bool?
    public let tailscaleHostname: String?
    public let throttlingFlags: [String]?
    public let runtimeMode: RuntimeMode?

    public struct DiskUsage: Codable, Sendable, Equatable, Hashable, Identifiable {
        public let mountpoint: String
        public let totalBytes: Double
        public let availableBytes: Double

        public init(mountpoint: String, totalBytes: Double, availableBytes: Double) {
            self.mountpoint = mountpoint
            self.totalBytes = totalBytes
            self.availableBytes = availableBytes
        }

        public var id: String { mountpoint }
        public var usedBytes: Double { max(0, totalBytes - availableBytes) }
        public var usedRatio: Double? {
            guard totalBytes > 0 else { return nil }
            return usedBytes / totalBytes
        }
    }

    public struct NetworkInterface: Codable, Sendable, Equatable, Hashable, Identifiable {
        public let name: String
        public let receivedBytes: Double
        public let transmittedBytes: Double

        public init(name: String, receivedBytes: Double, transmittedBytes: Double) {
            self.name = name
            self.receivedBytes = receivedBytes
            self.transmittedBytes = transmittedBytes
        }

        public var id: String { name }
    }

    public init(
        boothId: String,
        capturedAt: Date,
        uptimeSeconds: Double? = nil,
        hostname: String? = nil,
        osVersion: String? = nil,
        kernelVersion: String? = nil,
        cpuTemperatureCelsius: Double? = nil,
        cpuUsageRatio: Double? = nil,
        cpuUsageRatioPerCore: [Double]? = nil,
        loadAverage1m: Double? = nil,
        loadAverage5m: Double? = nil,
        loadAverage15m: Double? = nil,
        memoryUsedBytes: Double? = nil,
        memoryTotalBytes: Double? = nil,
        swapUsedBytes: Double? = nil,
        swapTotalBytes: Double? = nil,
        disks: [DiskUsage]? = nil,
        networkInterfaces: [NetworkInterface]? = nil,
        audioInputDevice: String? = nil,
        audioOutputDevice: String? = nil,
        audioInputDbfs: Double? = nil,
        audioOutputDbfs: Double? = nil,
        tailscaleConnected: Bool? = nil,
        tailscaleHostname: String? = nil,
        throttlingFlags: [String]? = nil,
        runtimeMode: RuntimeMode? = nil
    ) {
        self.boothId = boothId
        self.capturedAt = capturedAt
        self.uptimeSeconds = uptimeSeconds
        self.hostname = hostname
        self.osVersion = osVersion
        self.kernelVersion = kernelVersion
        self.cpuTemperatureCelsius = cpuTemperatureCelsius
        self.cpuUsageRatio = cpuUsageRatio
        self.cpuUsageRatioPerCore = cpuUsageRatioPerCore
        self.loadAverage1m = loadAverage1m
        self.loadAverage5m = loadAverage5m
        self.loadAverage15m = loadAverage15m
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.disks = disks
        self.networkInterfaces = networkInterfaces
        self.audioInputDevice = audioInputDevice
        self.audioOutputDevice = audioOutputDevice
        self.audioInputDbfs = audioInputDbfs
        self.audioOutputDbfs = audioOutputDbfs
        self.tailscaleConnected = tailscaleConnected
        self.tailscaleHostname = tailscaleHostname
        self.throttlingFlags = throttlingFlags
        self.runtimeMode = runtimeMode
    }

    public var memoryUsedRatio: Double? {
        guard let used = memoryUsedBytes, let total = memoryTotalBytes, total > 0 else {
            return nil
        }
        return used / total
    }

    public var swapUsedRatio: Double? {
        guard let used = swapUsedBytes, let total = swapTotalBytes, total > 0 else {
            return nil
        }
        return used / total
    }

    /// Inferred CPU core count from the per-core usage array, when present.
    public var cpuCoreCount: Int? {
        guard let cores = cpuUsageRatioPerCore, !cores.isEmpty else { return nil }
        return cores.count
    }
}

/// Envelope returned by `GET /v1/system/current?boothId=...` and the
/// items inside `GET /v1/system/current` (list form). Matches the
/// operator's `BoothSystemSnapshotEnvelopeSchema`.
public struct BoothSystemSnapshotEnvelope: Codable, Sendable, Equatable, Identifiable {
    public let boothId: String
    public let snapshot: BoothSystemSnapshot
    public let receivedAt: Date

    public init(boothId: String, snapshot: BoothSystemSnapshot, receivedAt: Date) {
        self.boothId = boothId
        self.snapshot = snapshot
        self.receivedAt = receivedAt
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
