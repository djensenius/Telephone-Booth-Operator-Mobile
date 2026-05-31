//
//  BoothSystemSnapshotTests.swift
//
//  Decoding coverage for the `/v1/system/current` envelope shapes and
//  the nested `BoothSystemSnapshot` mirror of the operator's Zod schema
//  (`packages/shared/src/index.ts`).
//

import XCTest
@testable import TBOperatorMobile

final class BoothSystemSnapshotTests: XCTestCase {

    func testEnvelopeWithFullSnapshot() throws {
        let envelope = try OperatorJSON.decoder.decode(
            BoothSystemSnapshotEnvelope.self,
            from: Data(Self.fullEnvelopeJSON.utf8)
        )
        XCTAssertEqual(envelope.boothId, "booth-a")
        XCTAssertEqual(envelope.version, "0.3.2")
        assertNestedFields(envelope.snapshot)
        assertLegacyShims(envelope.snapshot)
    }

    private func assertNestedFields(_ snapshot: BoothSystemSnapshot) {
        XCTAssertEqual(snapshot.cpu?.usageRatio, 0.32)
        XCTAssertEqual(snapshot.cpu?.perCoreUsageRatio?.count, 4)
        XCTAssertEqual(snapshot.cpu?.physicalCores, 4)
        XCTAssertEqual(snapshot.memory?.usedBytes, 1_500_000_000)
        XCTAssertEqual(snapshot.memory?.swapTotalBytes, 1_000_000_000)
        XCTAssertEqual(snapshot.disks?.first?.mountPoint, "/")
        XCTAssertEqual(snapshot.disks?.first?.filesystem, "ext4")
        XCTAssertEqual(snapshot.networks?.first?.interface, "eth0")
        XCTAssertEqual(snapshot.networks?.first?.receiveBytesTotal, 1024)
        XCTAssertEqual(snapshot.networks?.first?.addresses, ["192.168.1.5", "fe80::1"])
        XCTAssertEqual(snapshot.networks?.first?.ipAddresses, ["192.168.1.5", "fe80::1"])
        XCTAssertEqual(snapshot.audio?.inputDevice, "USB Mic")
        XCTAssertEqual(snapshot.audio?.sampleRateHz, 48000)
        XCTAssertEqual(snapshot.tailscale?.hostname, "booth-a.tailnet.ts.net")
        XCTAssertEqual(snapshot.tailscale?.connected, true)
        XCTAssertEqual(snapshot.tailscale?.peerCount, 5)
        XCTAssertNil(snapshot.tailscale?.exitNode)
        XCTAssertEqual(snapshot.throttling?.throttled, true)
        XCTAssertEqual(snapshot.process?.threads, 6)
        XCTAssertEqual(snapshot.runtimeMode, .real)
        XCTAssertEqual(snapshot.hostname, "booth-a-pi")
    }

    private func assertLegacyShims(_ snapshot: BoothSystemSnapshot) {
        XCTAssertEqual(snapshot.cpuTemperatureCelsius, 48.5)
        XCTAssertEqual(snapshot.cpuUsageRatio, 0.32)
        XCTAssertEqual(snapshot.loadAverage1m, 0.4)
        XCTAssertEqual(snapshot.memoryUsedBytes, 1_500_000_000)
        XCTAssertEqual(snapshot.networkInterfaces?.first?.name, "eth0")
        XCTAssertEqual(snapshot.disks?.first?.mountpoint, "/")
        XCTAssertEqual(snapshot.tailscaleConnected, true)
        XCTAssertEqual(snapshot.tailscaleHostname, "booth-a.tailnet.ts.net")
        XCTAssertEqual(snapshot.audioInputDevice, "USB Mic")
        XCTAssertNil(snapshot.audioInputDbfs)
        XCTAssertEqual(
            snapshot.throttlingFlags,
            ["throttled", "undervoltageOccurred", "throttledOccurred"]
        )
        XCTAssertEqual(snapshot.cpuCoreCount, 4)
    }

    private static let fullEnvelopeJSON = """
    {
      "boothId": "booth-a",
      "receivedAt": "2026-06-01T12:00:00Z",
      "version": "0.3.2",
      "snapshot": {
        "hostname": "booth-a-pi",
        "osVersion": "Debian 12",
        "kernelVersion": "Linux 6.6.0",
        "uptimeSeconds": 3600,
        "temperatureCelsius": 48.5,
        "cpu": {
          "usageRatio": 0.32,
          "perCoreUsageRatio": [0.1, 0.4, 0.5, 0.3],
          "physicalCores": 4,
          "loadAvg1m": 0.4,
          "loadAvg5m": 0.5,
          "loadAvg15m": 0.45
        },
        "memory": {
          "totalBytes": 4000000000,
          "usedBytes": 1500000000,
          "swapTotalBytes": 1000000000,
          "swapUsedBytes": 100000
        },
        "disks": [
          {"mountPoint": "/", "filesystem": "ext4", "totalBytes": 32000000000, "availableBytes": 24000000000}
        ],
        "networks": [
          {"interface": "eth0", "receiveBytesTotal": 1024, "transmitBytesTotal": 2048,
           "addresses": ["192.168.1.5", "fe80::1"]}
        ],
        "audio": {
          "inputDevice": "USB Mic",
          "outputDevice": "Handset",
          "sampleRateHz": 48000
        },
        "tailscale": {
          "connected": true,
          "peerCount": 5,
          "hostname": "booth-a.tailnet.ts.net",
          "exitNode": null
        },
        "throttling": {
          "undervoltage": false,
          "armFreqCapped": false,
          "throttled": true,
          "softTempLimit": false,
          "undervoltageOccurred": true,
          "throttledOccurred": true
        },
        "process": {
          "residentBytes": 12000000,
          "virtualBytes": 50000000,
          "openFds": 24,
          "threads": 6,
          "uptimeSeconds": 1800
        },
        "runtimeMode": "real"
      }
    }
    """

    func testEnvelopeListShape() throws {
        let json = """
        {
          "items": [
            {
              "boothId": "booth-a",
              "receivedAt": "2026-06-01T12:00:00Z",
              "snapshot": {
                "cpu": {"usageRatio": 0.1}
              }
            }
          ]
        }
        """
        let list = try OperatorJSON.decoder.decode(
            BoothSystemSnapshotList.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items.first?.boothId, "booth-a")
        XCTAssertEqual(list.items.first?.snapshot.cpu?.usageRatio, 0.1)
    }

    func testSnapshotWithOnlyTopLevelFieldsDecodes() throws {
        // Adapters that report only a subset of metrics should still
        // decode cleanly — every field is optional.
        let json = """
        {
          "temperatureCelsius": 50.0,
          "memory": {"usedBytes": 1000, "totalBytes": 2000}
        }
        """
        let snapshot = try OperatorJSON.decoder.decode(
            BoothSystemSnapshot.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(snapshot.cpuTemperatureCelsius, 50.0)
        XCTAssertEqual(snapshot.memoryUsedRatio, 0.5)
        XCTAssertNil(snapshot.cpu)
        XCTAssertNil(snapshot.disks)
        XCTAssertNil(snapshot.runtimeMode)
        XCTAssertNil(snapshot.throttlingFlags) // no throttling sub-object reported
    }

    func testSwapAndCoreHelpers() {
        let snapshot = BoothSystemSnapshot(
            cpu: .init(
                perCoreUsageRatio: [0.1, 0.2, 0.3, 0.4],
                physicalCores: 4
            ),
            memory: .init(
                swapTotalBytes: 1000,
                swapUsedBytes: 250
            )
        )
        XCTAssertEqual(snapshot.swapUsedRatio, 0.25)
        XCTAssertEqual(snapshot.cpuCoreCount, 4)
    }

    func testEmptyThrottlingFlagsArrayWhenAllFalse() {
        let snapshot = BoothSystemSnapshot(
            throttling: .init(
                undervoltage: false,
                armFreqCapped: false,
                throttled: false,
                softTempLimit: false,
                undervoltageOccurred: false,
                throttledOccurred: false
            )
        )
        // Sub-object was reported, so shim returns an array (possibly empty),
        // distinguishing "throttling subsystem reporting cleanly" from
        // "throttling subsystem not available".
        XCTAssertEqual(snapshot.throttlingFlags, [])
    }
}
