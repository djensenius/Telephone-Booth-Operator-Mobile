//
//  StatusSocket.swift
//  TelephoneBoothOperatorMobile
//
//  Bearer-authenticated WebSocket client for the operator's live booth
//  status feed at /v1/ws/status.
//

import Foundation
import os

private let statusSocketLogger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "StatusSocket"
)

public enum WsStatusEnvelope: Decodable, Sendable, Equatable {
    case status(BoothStatus)
    case system(BoothSystemSnapshotEnvelope)
    case message(Message)

    private enum CodingKeys: String, CodingKey {
        case kind
        case status
        case boothId
        case snapshot
        case receivedAt
        case version
        case message
    }

    private enum Kind: String, Decodable {
        case status
        case system
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .status:
            self = .status(try container.decode(BoothStatus.self, forKey: .status))
        case .system:
            let envelope = BoothSystemSnapshotEnvelope(
                boothId: try container.decode(String.self, forKey: .boothId),
                snapshot: try container.decode(BoothSystemSnapshot.self, forKey: .snapshot),
                receivedAt: try container.decode(Date.self, forKey: .receivedAt),
                version: try container.decodeIfPresent(String.self, forKey: .version)
            )
            self = .system(envelope)
        case .message:
            self = .message(try container.decode(Message.self, forKey: .message))
        }
    }
}

public actor StatusSocket {
    @MainActor public static let shared = StatusSocket(
        config: AppConfig.shared,
        auth: AuthManager.shared
    )
    @MainActor public static let demo = StatusSocket(
        config: AppConfig.shared,
        auth: AuthManager.shared,
        demoMode: true
    )

    public static let defaultMaxMessageSize = 1_048_576

    /// A single inbound WebSocket frame, normalized for processing and tests.
    enum IncomingMessage: Sendable {
        case data(Data)
        case text(String)
    }

    private let config: AppConfig?
    private let auth: AuthManager?
    private let session: URLSession
    private let maxMessageSize: Int
    private let demoMode: Bool

    public init(
        config: AppConfig,
        auth: AuthManager,
        session: URLSession = .shared,
        maxMessageSize: Int = StatusSocket.defaultMaxMessageSize,
        demoMode: Bool = false
    ) {
        self.config = config
        self.auth = auth
        self.session = session
        self.maxMessageSize = maxMessageSize
        self.demoMode = demoMode
    }

    /// Test hook that builds a socket without config/auth so message
    /// processing can be exercised deterministically.
    init(maxMessageSize: Int) {
        self.config = nil
        self.auth = nil
        self.session = .shared
        self.maxMessageSize = maxMessageSize
        self.demoMode = false
    }

    public nonisolated func subscribe() -> AsyncThrowingStream<WsStatusEnvelope, Error> {
        if demoMode {
            return DemoData.statusSocketStream()
        }
        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.run(continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static func webSocketURL(from apiBaseURL: URL) throws -> URL {
        guard var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else {
            throw OperatorError.invalidURL
        }
        switch scheme {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        default:
            throw OperatorError.invalidURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "/v1/ws/status" : "/\(basePath)/v1/ws/status"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw OperatorError.invalidURL }
        return url
    }

    private func run(
        continuation: AsyncThrowingStream<WsStatusEnvelope, Error>.Continuation
    ) async throws {
        var didRetry = false
        while true {
            let request = try await buildRequest()
            let task = session.webSocketTask(with: request)
            task.resume()
            do {
                try await receive(from: task, continuation: continuation)
                return
            } catch is CancellationError {
                task.cancel(with: .goingAway, reason: nil)
                throw CancellationError()
            } catch {
                if isUnauthorizedClose(task.closeCode),
                   !didRetry,
                   let auth,
                   await auth.refreshTokenIfNeeded() {
                    statusSocketLogger.info(
                        "/v1/ws/status closed as unauthorized, refreshed token and reconnecting once"
                    )
                    didRetry = true
                    continue
                }
                throw error
            }
        }
    }

    private func buildRequest() async throws -> URLRequest {
        guard let config, let auth else { throw OperatorError.invalidURL }
        let url = try await StatusSocket.webSocketURL(from: config.apiBaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = .infinity
        guard let header = await auth.authorizationHeader() else {
            throw OperatorError.unauthenticated
        }
        request.setValue(header, forHTTPHeaderField: "Authorization")
        return request
    }

    private func receive(
        from task: URLSessionWebSocketTask,
        continuation: AsyncThrowingStream<WsStatusEnvelope, Error>.Continuation
    ) async throws {
        while !Task.isCancelled {
            let incoming: IncomingMessage
            switch try await task.receive() {
            case .data(let payload):
                incoming = .data(payload)
            case .string(let text):
                incoming = .text(text)
            @unknown default:
                statusSocketLogger.debug("Ignoring unknown WebSocket message type")
                continue
            }
            try handle(incoming, task: task, continuation: continuation)
        }
    }

    /// Enforces the size limit and decodes a single frame into a
    /// `WsStatusEnvelope`. Extracted so tests can exercise the size guard and
    /// decoding without a live transport. On an oversized frame the socket is
    /// closed with `.messageTooBig` before throwing so the connection does not
    /// linger.
    func handle(
        _ message: IncomingMessage,
        task: URLSessionWebSocketTask? = nil,
        continuation: AsyncThrowingStream<WsStatusEnvelope, Error>.Continuation
    ) throws {
        let data: Data
        switch message {
        case .data(let payload):
            data = payload
        case .text(let text):
            data = Data(text.utf8)
        }
        guard data.count <= maxMessageSize else {
            statusSocketLogger.error(
                "Status WebSocket message exceeded max size of \(self.maxMessageSize) bytes"
            )
            task?.cancel(with: .messageTooBig, reason: nil)
            throw OperatorError.eventSizeExceeded(maxMessageSize)
        }
        do {
            continuation.yield(try OperatorJSON.decoder.decode(WsStatusEnvelope.self, from: data))
        } catch {
            statusSocketLogger.error(
                "Status WebSocket decode failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func isUnauthorizedClose(_ code: URLSessionWebSocketTask.CloseCode) -> Bool {
        code == .policyViolation
    }
}

extension DemoData {
    public static func statusSocketStream() -> AsyncThrowingStream<WsStatusEnvelope, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    continuation.yield(.status(boothStatus))
                    continuation.yield(.system(systemEnvelope))
                    try? await Task.sleep(for: .seconds(5))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
