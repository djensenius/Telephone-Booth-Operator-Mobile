//
//  EventStream.swift
//  TelephoneBoothOperatorMobile
//
//  Async SSE (Server-Sent Events) reader for /v1/events/stream. The operator
//  emits three event types: "booth-event" (a JSON-encoded BoothEventRecord),
//  "ping" (keep-alive heartbeat, every 15s), and "ready" (one-shot on
//  connect). We only surface booth-events to consumers.
//

import Foundation
import os

private let logger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "EventStream"
)

public struct EventStreamFilters: Sendable, Equatable {
    public var boothId: String?
    public var sessionId: String?
    public var type: BoothEventType?

    public init(
        boothId: String? = nil,
        sessionId: String? = nil,
        type: BoothEventType? = nil
    ) {
        self.boothId = boothId
        self.sessionId = sessionId
        self.type = type
    }
}

public actor EventStream {
    @MainActor public static let shared = EventStream(
        config: AppConfig.shared,
        auth: AuthManager.shared
    )

    /// Maximum allowed size (in bytes) of a single SSE event's accumulated data
    /// lines before the stream is terminated with an error. Default: 1 MB.
    public static let defaultMaxEventSize = 1_048_576

    private let config: AppConfig?
    private let auth: AuthManager?
    private let session: URLSession
    private let maxEventSize: Int

    public init(
        config: AppConfig,
        auth: AuthManager,
        session: URLSession = .shared,
        maxEventSize: Int = EventStream.defaultMaxEventSize
    ) {
        self.config = config
        self.auth = auth
        self.session = session
        self.maxEventSize = maxEventSize
    }

    /// Test-only initialiser. The returned actor cannot subscribe to a
    /// real `/v1/events` connection — it exists purely to exercise the
    /// SSE parser via `consumeLines(_:continuation:)`.
    internal init(maxEventSize: Int) {
        self.config = nil
        self.auth = nil
        self.session = .shared
        self.maxEventSize = maxEventSize
    }

    /// Returns an AsyncThrowingStream of booth events. The stream is
    /// finished when the underlying HTTP connection closes; consumers are
    /// expected to reconnect with backoff if they want to keep tailing.
    public nonisolated func subscribe(
        filters: EventStreamFilters = EventStreamFilters()
    ) -> AsyncThrowingStream<BoothEventRecord, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.run(filters: filters, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func run(
        filters: EventStreamFilters,
        continuation: AsyncThrowingStream<BoothEventRecord, Error>.Continuation
    ) async throws {
        let request = try await buildRequest(filters: filters)
        let (bytes, response) = try await session.bytes(for: request)
        try validate(response: response)
        try await consume(bytes: bytes, continuation: continuation)
    }

    private func buildRequest(filters: EventStreamFilters) async throws -> URLRequest {
        guard let config, let auth else {
            throw OperatorError.invalidURL
        }
        var components = URLComponents(
            url: await config.url(forPath: "/v1/events/stream"),
            resolvingAgainstBaseURL: false
        )
        var items: [URLQueryItem] = []
        if let id = filters.boothId { items.append(URLQueryItem(name: "boothId", value: id)) }
        if let id = filters.sessionId { items.append(URLQueryItem(name: "sessionId", value: id)) }
        if let type = filters.type { items.append(URLQueryItem(name: "type", value: type.rawValue)) }
        components?.queryItems = items.isEmpty ? nil : items
        guard let url = components?.url else { throw OperatorError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = .infinity
        guard let header = await auth.authorizationHeader() else {
            throw OperatorError.unauthenticated
        }
        request.setValue(header, forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OperatorError.transport(URLError(.badServerResponse))
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw OperatorError.unauthorized("")
        }
        guard (200...299).contains(http.statusCode) else {
            throw OperatorError.httpError(status: http.statusCode, body: "")
        }
    }

    private func consume(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<BoothEventRecord, Error>.Continuation
    ) async throws {
        try await consumeLines(bytes.lines, continuation: continuation)
    }

    /// Parses an async sequence of SSE lines, dispatching complete events.
    /// Throws `OperatorError.eventSizeExceeded` if accumulated data lines
    /// exceed `maxEventSize` before a blank-line delimiter arrives.
    func consumeLines<S: AsyncSequence>(
        _ lines: S,
        continuation: AsyncThrowingStream<BoothEventRecord, Error>.Continuation
    ) async throws where S.Element == String {
        var currentEvent = "message"
        var dataBuffer = ""
        for try await line in lines {
            if Task.isCancelled { break }
            if line.isEmpty {
                try dispatch(event: currentEvent, data: dataBuffer, continuation: continuation)
                currentEvent = "message"
                dataBuffer = ""
                continue
            }
            parse(line: line, currentEvent: &currentEvent, dataBuffer: &dataBuffer)
            if dataBuffer.utf8.count > maxEventSize {
                logger.error("SSE event exceeded max size of \(self.maxEventSize) bytes, dropping connection")
                throw OperatorError.eventSizeExceeded(maxEventSize)
            }
        }
    }

    private func parse(line: String, currentEvent: inout String, dataBuffer: inout String) {
        if line.hasPrefix(":") { return }
        if let value = strip(prefix: "event:", from: line) {
            currentEvent = value
            return
        }
        if let value = strip(prefix: "data:", from: line) {
            if dataBuffer.isEmpty {
                dataBuffer = value
            } else {
                dataBuffer += "\n" + value
            }
        }
    }

    private func dispatch(
        event: String,
        data: String,
        continuation: AsyncThrowingStream<BoothEventRecord, Error>.Continuation
    ) throws {
        guard event == "booth-event", !data.isEmpty else { return }
        do {
            let record = try OperatorJSON.decoder.decode(BoothEventRecord.self, from: Data(data.utf8))
            continuation.yield(record)
        } catch {
            logger.error("SSE decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func strip(prefix: String, from line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        var value = String(line.dropFirst(prefix.count))
        if value.first == " " { value.removeFirst() }
        return value
    }
}
