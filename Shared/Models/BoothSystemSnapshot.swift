//
//  BoothSystemSnapshot.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public struct BoothSystemSnapshot: Codable, Sendable, Equatable {
    public let boothId: String
    public let capturedAt: Date
    public let uptimeSeconds: Double?
    public let cpuTemperatureCelsius: Double?
    public let cpuUsageRatio: Double?
    public let loadAverage1m: Double?
    public let loadAverage5m: Double?
    public let loadAverage15m: Double?
    public let memoryUsedBytes: Double?
    public let memoryTotalBytes: Double?
    public let tailscaleConnected: Bool?
    public let throttlingFlags: [String]?

    public init(
        boothId: String,
        capturedAt: Date,
        uptimeSeconds: Double?,
        cpuTemperatureCelsius: Double?,
        cpuUsageRatio: Double?,
        loadAverage1m: Double?,
        loadAverage5m: Double?,
        loadAverage15m: Double?,
        memoryUsedBytes: Double?,
        memoryTotalBytes: Double?,
        tailscaleConnected: Bool?,
        throttlingFlags: [String]?
    ) {
        self.boothId = boothId
        self.capturedAt = capturedAt
        self.uptimeSeconds = uptimeSeconds
        self.cpuTemperatureCelsius = cpuTemperatureCelsius
        self.cpuUsageRatio = cpuUsageRatio
        self.loadAverage1m = loadAverage1m
        self.loadAverage5m = loadAverage5m
        self.loadAverage15m = loadAverage15m
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.tailscaleConnected = tailscaleConnected
        self.throttlingFlags = throttlingFlags
    }

    enum CodingKeys: String, CodingKey {
        case boothId, capturedAt
        case uptimeSeconds, cpuTemperatureCelsius, cpuUsageRatio
        case loadAverage1m, loadAverage5m, loadAverage15m
        case memoryUsedBytes, memoryTotalBytes
        case tailscaleConnected, throttlingFlags
    }

    public var memoryUsedRatio: Double? {
        guard let used = memoryUsedBytes, let total = memoryTotalBytes, total > 0 else {
            return nil
        }
        return used / total
    }
}

public struct StatusHistory: Codable, Sendable, Equatable {
    public let items: [BoothStatus]

    public init(items: [BoothStatus]) {
        self.items = items
    }
}
