//
//  EventStreamTests.swift
//

import XCTest
@testable import TBOperatorMobile

/// An async sequence that yields lines from an array.
private struct MockLines: AsyncSequence {
    typealias Element = String
    let lines: [String]

    struct AsyncIterator: AsyncIteratorProtocol {
        var index: Int = 0
        let lines: [String]
        mutating func next() async -> String? {
            guard index < lines.count else { return nil }
            defer { index += 1 }
            return lines[index]
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(lines: lines)
    }
}

final class EventStreamTests: XCTestCase {

    // MARK: - Helpers

    private func makeStream(
        maxEventSize: Int
    ) -> (EventStream, AsyncThrowingStream<BoothEventRecord, Error>.Continuation) {
        let stream = EventStream(maxEventSize: maxEventSize)
        var capturedContinuation: AsyncThrowingStream<BoothEventRecord, Error>.Continuation!
        _ = AsyncThrowingStream<BoothEventRecord, Error> { continuation in
            capturedContinuation = continuation
        }
        return (stream, capturedContinuation)
    }

    // MARK: - Tests

    func testNormalEventDoesNotExceedLimit() async throws {
        let (stream, continuation) = makeStream(maxEventSize: 1024)
        let lines = MockLines(lines: [
            "event: booth-event",
            "data: {\"id\":\"1\",\"eventId\":\"e1\",\"boothId\":\"b\",\"bootId\":\"x\"," +
            "\"type\":\"call_started\",\"occurredAt\":\"2026-05-23T14:32:00Z\"," +
            "\"receivedAt\":\"2026-05-23T14:32:00Z\",\"sessionId\":null,\"recordingId\":null}",
            ""
        ])

        // Should complete without throwing
        try await stream.consumeLines(lines, continuation: continuation)
        continuation.finish()
    }

    func testOversizedEventThrowsError() async {
        let maxSize = 64
        let (stream, continuation) = makeStream(maxEventSize: maxSize)
        // Build a data payload that exceeds maxSize
        let bigPayload = String(repeating: "x", count: maxSize + 1)
        let lines = MockLines(lines: [
            "event: booth-event",
            "data: \(bigPayload)"
            // No blank line — the overflow check fires before we even get there
        ])

        do {
            try await stream.consumeLines(lines, continuation: continuation)
            XCTFail("Expected eventSizeExceeded error")
        } catch let error as OperatorError {
            switch error {
            case .eventSizeExceeded(let limit):
                XCTAssertEqual(limit, maxSize)
            default:
                XCTFail("Unexpected OperatorError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        continuation.finish()
    }

    func testMultipleDataLinesAccumulateAndExceedLimit() async {
        let maxSize = 100
        let (stream, continuation) = makeStream(maxEventSize: maxSize)
        // Each line is 40 chars of data; 3 lines = 40 + 1 + 40 + 1 + 40 = 122 bytes > 100
        let chunk = String(repeating: "a", count: 40)
        let lines = MockLines(lines: [
            "event: booth-event",
            "data: \(chunk)",
            "data: \(chunk)",
            "data: \(chunk)"
        ])

        do {
            try await stream.consumeLines(lines, continuation: continuation)
            XCTFail("Expected eventSizeExceeded error")
        } catch let error as OperatorError {
            switch error {
            case .eventSizeExceeded(let limit):
                XCTAssertEqual(limit, maxSize)
            default:
                XCTFail("Unexpected OperatorError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        continuation.finish()
    }

    func testBufferResetsAfterSuccessfulDispatch() async throws {
        let maxSize = 100
        let (stream, continuation) = makeStream(maxEventSize: maxSize)
        // First event: 50 bytes of data (under limit), then blank line resets
        // Second event: another 50 bytes (under limit)
        let chunk = String(repeating: "b", count: 50)
        let lines = MockLines(lines: [
            "event: ping",
            "data: \(chunk)",
            "",  // dispatch + reset
            "event: ping",
            "data: \(chunk)",
            ""   // dispatch + reset
        ])

        // Should not throw — each event individually is under the limit
        try await stream.consumeLines(lines, continuation: continuation)
        continuation.finish()
    }

    func testDefaultMaxEventSize() {
        XCTAssertEqual(EventStream.defaultMaxEventSize, 1_048_576)
    }
}
