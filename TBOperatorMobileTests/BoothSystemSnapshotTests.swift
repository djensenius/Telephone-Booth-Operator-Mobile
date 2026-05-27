//
//  BoothSystemSnapshotTests.swift
//
//  Decoding coverage for the `/v1/system/current` envelope shapes and
//  the expanded fields synced from the operator's Zod schema.
//

import XCTest
@testable import TBOperatorMobile

final class BoothSystemSnapshotTests: XCTestCase {

    func testEnvelopeWithFullSnapshot() throws {
        let json = """
        {
          "boothId": "booth-a",
          "receivedAt": "2026-06-01T12:00:00Z",
          "snapshot": {
            "boothId": "booth-a",
            "capturedAt": "2026-06-01T11:59:55Z",
            "hostname": "booth-a-pi",
            "osVersion": "Debian 12",
            "kernelVersion": "Linux 6.6.0",
            "uptimeSeconds": 3600,
            "cpuTemperatureCelsius": 48.5,
            "cpuUsageRatio": 0.32,
            "cpuUsageRatioPerCore": [0.1, 0.4, 0.5, 0.3],
            "loadAverage1m": 0.4,
            "loadAverage5m": 0.5,
            "loadAverage15m": 0.45,
            "memoryUsedBytes": 1500000000,
            "memoryTotalBytes": 4000000000,
            "swapUsedBytes": 100000,
            "swapTotalBytes": 1000000000,
            "disks": [
              {"mountpoint": "/", "totalBytes": 32000000000, "availableBytes": 24000000000}
            ],
            "networkInterfaces": [
              {"name": "eth0", "receivedBytes": 1024, "transmittedBytes": 2048}
            ],
            "audioInputDevice": "USB Mic",
            "audioOutputDevice": "Handset",
            "audioInputDbfs": -22.5,
            "audioOutputDbfs": -12.0,
            "tailscaleConnected": true,
            "tailscaleHostname": "booth-a.tailnet.ts.net",
            "throttlingFlags": [],
            "runtimeMode": "real"
          }
        }
        """
        let envelope = try OperatorJSON.decoder.decode(
            BoothSystemSnapshotEnvelope.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(envelope.boothId, "booth-a")
        let snapshot = envelope.snapshot
        XCTAssertEqual(snapshot.hostname, "booth-a-pi")
        XCTAssertEqual(snapshot.osVersion, "Debian 12")
        XCTAssertEqual(snapshot.kernelVersion, "Linux 6.6.0")
        XCTAssertEqual(snapshot.cpuUsageRatioPerCore?.count, 4)
        XCTAssertEqual(snapshot.swapTotalBytes, 1_000_000_000)
        XCTAssertEqual(snapshot.disks?.first?.mountpoint, "/")
        XCTAssertEqual(snapshot.networkInterfaces?.first?.name, "eth0")
        XCTAssertEqual(snapshot.audioInputDevice, "USB Mic")
        XCTAssertEqual(snapshot.audioInputDbfs, -22.5)
        XCTAssertEqual(snapshot.tailscaleHostname, "booth-a.tailnet.ts.net")
        XCTAssertEqual(snapshot.runtimeMode, .real)
    }

    func testEnvelopeListShape() throws {
        let json = """
        {
          "items": [
            {
              "boothId": "booth-a",
              "receivedAt": "2026-06-01T12:00:00Z",
              "snapshot": {
                "boothId": "booth-a",
                "capturedAt": "2026-06-01T11:59:55Z"
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
    }

    func testSnapshotMissingNewFieldsStillDecodes() throws {
        let json = """
        {
          "boothId": "booth-a",
          "capturedAt": "2026-06-01T11:59:55Z",
          "cpuTemperatureCelsius": 50.0,
          "memoryUsedBytes": 1000,
          "memoryTotalBytes": 2000
        }
        """
        let snapshot = try OperatorJSON.decoder.decode(
            BoothSystemSnapshot.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(snapshot.boothId, "booth-a")
        XCTAssertEqual(snapshot.cpuTemperatureCelsius, 50.0)
        XCTAssertEqual(snapshot.memoryUsedRatio, 0.5)
        XCTAssertNil(snapshot.hostname)
        XCTAssertNil(snapshot.disks)
        XCTAssertNil(snapshot.runtimeMode)
    }

    func testSwapAndCoreHelpers() {
        let snapshot = BoothSystemSnapshot(
            boothId: "x",
            capturedAt: Date(),
            cpuUsageRatioPerCore: [0.1, 0.2, 0.3, 0.4],
            swapUsedBytes: 250,
            swapTotalBytes: 1000
        )
        XCTAssertEqual(snapshot.swapUsedRatio, 0.25)
        XCTAssertEqual(snapshot.cpuCoreCount, 4)
    }
}
