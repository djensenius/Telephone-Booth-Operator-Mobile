//
//  OperatorClient.swift
//  TelephoneBoothOperatorMobile
//
//  Typed REST client over the operator API. Bearer tokens come from
//  `AuthManager`; every request goes through `ensureValidToken()` so an
//  in-flight refresh is awaited before issuing the request.
//

import Foundation
import os

private let logger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "OperatorClient"
)

/// Read-only operator REST client. Expansion happens in PR 3+ as the UI
/// adds dashboards, sessions, messages, moderation, etc.
public actor OperatorClient {
    @MainActor public static let shared = OperatorClient(
        config: AppConfig.shared,
        auth: AuthManager.shared
    )

    private let config: AppConfig
    private let auth: AuthManager
    private let session: URLSession

    public init(
        config: AppConfig,
        auth: AuthManager,
        session: URLSession = .shared
    ) {
        self.config = config
        self.auth = auth
        self.session = session
    }

    // MARK: - Endpoints

    /// `GET /v1/auth/me` — returns the operator profile derived from the
    /// bearer token claims.
    public func fetchMe() async throws -> OperatorMe {
        try await get("/v1/auth/me")
    }

    /// `GET /v1/stats/summary` — booth health + queue counts. Operator
    /// caches this for 5s, so 15-minute widget polling is cheap.
    public func fetchStatsSummary() async throws -> StatsSummary {
        try await get("/v1/stats/summary")
    }

    /// `GET /v1/status` — current booth state (no auth required, but we
    /// still send the bearer if available so the operator can correlate
    /// access in logs).
    public func fetchBoothStatus() async throws -> BoothStatus {
        try await get("/v1/status", requireAuth: false)
    }

    /// `GET /v1/status/history` — recent booth status snapshots used to
    /// render the uptime chart. `since` is optional; default `limit` is
    /// 100 (server caps at 500).
    public func fetchStatusHistory(since: Date? = nil, limit: Int = 100) async throws -> StatusHistory {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let since {
            items.append(URLQueryItem(name: "since", value: OperatorJSON.iso8601String(from: since)))
        }
        return try await get("/v1/status/history", query: items)
    }

    /// `GET /v1/sessions` — paged call sessions. `cursor` is the opaque
    /// token returned in the previous page's `nextCursor`.
    public func fetchSessions(
        boothId: String? = nil,
        cursor: String? = nil,
        limit: Int = 50
    ) async throws -> SessionListPage {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let boothId { items.append(URLQueryItem(name: "boothId", value: boothId)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get("/v1/sessions", query: items)
    }

    /// `GET /v1/sessions/{id}` — one session with its ordered events.
    public func fetchSession(id: String) async throws -> CallSessionDetail {
        try await get("/v1/sessions/\(id)")
    }

    /// `GET /v1/system/current` — latest cached system snapshot for one
    /// booth, or all booths when `boothId` is nil.
    public func fetchCurrentSystem(boothId: String? = nil) async throws -> BoothSystemSnapshot? {
        let items = boothId.map { [URLQueryItem(name: "boothId", value: $0)] } ?? []
        // The endpoint returns 404 when no snapshot has ever been pushed;
        // that's not an error from the UI's perspective, just "no data yet".
        do {
            return try await get("/v1/system/current", query: items)
        } catch let OperatorError.httpError(status, _) where status == 404 {
            return nil
        }
    }

    /// `GET /v1/messages` — list (filterable by status, since, limit).
    public func fetchMessages(
        status: MessageStatus? = nil,
        since: Date? = nil,
        limit: Int = 50
    ) async throws -> MessageList {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let status { items.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let since {
            items.append(URLQueryItem(name: "since", value: OperatorJSON.iso8601String(from: since)))
        }
        return try await get("/v1/messages", query: items)
    }

    /// `GET /v1/messages/{id}` — single message, including a freshly-
    /// signed audio URL on `audio.url`.
    public func fetchMessage(id: String) async throws -> Message {
        try await get("/v1/messages/\(id)")
    }

    /// `GET /v1/messages/{id}/transcriptions` — every transcription
    /// attempt for the message, newest first.
    public func fetchTranscriptions(messageId: String) async throws -> TranscriptionList {
        try await get("/v1/messages/\(messageId)/transcriptions")
    }

    /// `POST /v1/messages/{id}/transcribe` — re-runs transcription (and
    /// downstream moderation). Returns the new `Transcription`.
    public func transcribeMessage(id: String) async throws -> Transcription {
        try await postEmpty("/v1/messages/\(id)/transcribe")
    }

    /// `POST /v1/messages/{id}/moderate` — re-runs AI moderation against
    /// the latest succeeded transcription. Returns the new `Moderation`.
    public func moderateMessage(id: String) async throws -> Moderation {
        try await postEmpty("/v1/messages/\(id)/moderate")
    }

    /// `GET /v1/events` — paged booth event log, newest first. `cursor` is
    /// the opaque token returned in the previous page's `nextCursor`.
    public func fetchEvents(
        boothId: String? = nil,
        type: BoothEventType? = nil,
        sessionId: String? = nil,
        since: Date? = nil,
        until: Date? = nil,
        cursor: String? = nil,
        limit: Int = 100
    ) async throws -> EventList {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let boothId { items.append(URLQueryItem(name: "boothId", value: boothId)) }
        if let type { items.append(URLQueryItem(name: "type", value: type.rawValue)) }
        if let sessionId { items.append(URLQueryItem(name: "sessionId", value: sessionId)) }
        if let since {
            items.append(URLQueryItem(name: "since", value: OperatorJSON.iso8601String(from: since)))
        }
        if let until {
            items.append(URLQueryItem(name: "until", value: OperatorJSON.iso8601String(from: until)))
        }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get("/v1/events", query: items)
    }

    /// `GET /v1/questions` — paged active questions, newest first.
    public func fetchQuestions(
        cursor: String? = nil,
        limit: Int = 50
    ) async throws -> QuestionList {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get("/v1/questions", query: items)
    }

    /// `DELETE /v1/questions/{id}` — soft-deletes (retires) a question.
    public func deleteQuestion(id: String) async throws {
        try await delete("/v1/questions/\(id)")
    }

    // MARK: - Mobile device registry

    /// `GET /v1/devices` — the caller's active mobile devices.
    public func fetchDevices() async throws -> [MobileDevice] {
        try await get("/v1/devices")
    }

    /// `POST /v1/devices` — register or refresh the APNs token. Server
    /// upserts on `(apnsToken, platform)` so calling this on every launch
    /// (after permission is granted) is the intended flow.
    public func registerDevice(_ body: RegisterMobileDeviceRequest) async throws -> MobileDevice {
        try await postJSON("/v1/devices", body: body)
    }

    /// `PATCH /v1/devices/{id}` — push a new preference set or device name
    /// to the server. Returns the merged record.
    public func updateDevice(
        id: String,
        body: UpdateMobileDevicePreferencesRequest
    ) async throws -> MobileDevice {
        try await request(method: "PATCH", path: "/v1/devices/\(id)", body: body, requireAuth: true)
    }

    /// `DELETE /v1/devices/{id}` — revoke a device. The server sets
    /// `revokedAt` so APNs delivery to that token stops immediately.
    public func revokeDevice(id: String) async throws {
        try await delete("/v1/devices/\(id)")
    }

    // MARK: - Core request helpers

    private func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        requireAuth: Bool = true
    ) async throws -> T {
        try await request(
            method: "GET",
            path: path,
            query: query,
            body: Optional<Data>.none,
            requireAuth: requireAuth
        )
    }

    private func postEmpty<T: Decodable>(_ path: String) async throws -> T {
        try await request(
            method: "POST",
            path: path,
            body: Optional<Data>.none,
            requireAuth: true
        )
    }

    private func postJSON<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        try await request(method: "POST", path: path, body: body, requireAuth: true)
    }

    private func delete(_ path: String) async throws {
        let url = await config.url(forPath: path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let header = await auth.authorizationHeader() else {
            throw OperatorError.unauthenticated
        }
        request.setValue(header, forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OperatorError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw OperatorError.transport(URLError(.badServerResponse))
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            logger.warning("\(path, privacy: .public) → \(http.statusCode)")
            throw OperatorError.unauthorized(String(data: data, encoding: .utf8) ?? "")
        }
        guard (200...299).contains(http.statusCode) else {
            throw OperatorError.httpError(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    private func request<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Body?,
        requireAuth: Bool = true
    ) async throws -> Response {
        let baseURL = await config.url(forPath: path)
        let url: URL
        if query.isEmpty {
            url = baseURL
        } else {
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw OperatorError.invalidURL
            }
            components.queryItems = (components.queryItems ?? []) + query
            guard let composed = components.url else { throw OperatorError.invalidURL }
            url = composed
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try OperatorJSON.encoder.encode(body)
            } catch {
                throw OperatorError.encoding(error)
            }
        }

        if requireAuth || await auth.getAccessToken() != nil {
            guard let header = await auth.authorizationHeader() else {
                if requireAuth { throw OperatorError.unauthenticated }
                // Optional auth and no token available — proceed unauthenticated.
                return try await perform(request, path: path)
            }
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }

        return try await perform(request, path: path)
    }

    private func perform<Response: Decodable>(_ request: URLRequest, path: String) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OperatorError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw OperatorError.transport(URLError(.badServerResponse))
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.warning("\(path, privacy: .public) → \(http.statusCode)")
            throw OperatorError.unauthorized(body)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OperatorError.httpError(status: http.statusCode, body: body)
        }

        do {
            return try OperatorJSON.decoder.decode(Response.self, from: data)
        } catch {
            throw OperatorError.decoding(error)
        }
    }
}
