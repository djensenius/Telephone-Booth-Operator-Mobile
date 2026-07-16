//
//  StatusSocketTests.swift
//

import XCTest
@testable import TBOperatorMobile

final class StatusSocketTests: XCTestCase {
    func testDecodeStatusEnvelope() throws {
        let data = Data("""
        {
          "kind": "status",
          "status": {
            "state": "recording",
            "updatedAt": "2026-07-16T22:30:00Z",
            "currentQuestionId": null,
            "currentMessageId": null,
            "lastError": null,
            "runtimeMode": "simulator"
          }
        }
        """.utf8)

        let envelope = try OperatorJSON.decoder.decode(WsStatusEnvelope.self, from: data)
        guard case .status(let status) = envelope else {
            return XCTFail("Expected status envelope")
        }
        XCTAssertEqual(status.state, .recording)
        XCTAssertEqual(status.runtimeMode, .simulator)
    }

    func testDecodeSystemEnvelope() throws {
        let data = Data("""
        {
          "kind": "system",
          "boothId": "booth-main",
          "snapshot": {
            "cpu": { "usageRatio": 0.42, "physicalCores": 4 },
            "temperatureCelsius": 51.5,
            "runtimeMode": "hardware"
          },
          "receivedAt": "2026-07-16T22:31:00.123Z",
          "version": "abc123"
        }
        """.utf8)

        let envelope = try OperatorJSON.decoder.decode(WsStatusEnvelope.self, from: data)
        guard case .system(let system) = envelope else {
            return XCTFail("Expected system envelope")
        }
        XCTAssertEqual(system.boothId, "booth-main")
        XCTAssertEqual(system.snapshot.cpuUsageRatio, 0.42)
        XCTAssertEqual(system.snapshot.cpuCoreCount, 4)
        XCTAssertEqual(system.version, "abc123")
    }

    func testDecodeMessageEnvelope() throws {
        let data = Data("""
        {
          "kind": "message",
          "message": {
            "id": "message-1",
            "status": "pending",
            "questionId": null,
            "notes": null,
            "createdAt": "2026-07-16T22:32:00Z",
            "receivedAt": "2026-07-16T22:32:01Z",
            "audio": {
              "url": "https://example.com/audio.m4a",
              "sha256": "abc",
              "durationMs": 1200
            },
            "latestTranscription": null,
            "latestModeration": null
          }
        }
        """.utf8)

        let envelope = try OperatorJSON.decoder.decode(WsStatusEnvelope.self, from: data)
        guard case .message(let message) = envelope else {
            return XCTFail("Expected message envelope")
        }
        XCTAssertEqual(message.id, "message-1")
        XCTAssertEqual(message.status, .pending)
        XCTAssertEqual(message.audio.durationMs, 1200)
    }

    func testWebSocketURLDerivation() throws {
        XCTAssertEqual(
            try StatusSocket.webSocketURL(from: URL(string: "https://api.telephonebooth.io")!).absoluteString,
            "wss://api.telephonebooth.io/v1/ws/status"
        )
        XCTAssertEqual(
            try StatusSocket.webSocketURL(from: URL(string: "http://localhost:3000/api")!).absoluteString,
            "ws://localhost:3000/api/v1/ws/status"
        )
    }
}
