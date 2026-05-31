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
    @MainActor public static let demo = OperatorClient(
        config: AppConfig.shared,
        auth: AuthManager.shared,
        demoMode: true
    )

    private let config: AppConfig
    private let auth: AuthManager
    private let session: URLSession
    private let demoMode: Bool

    public init(
        config: AppConfig,
        auth: AuthManager,
        session: URLSession = .shared,
        demoMode: Bool = false
    ) {
        self.config = config
        self.auth = auth
        self.session = session
        self.demoMode = demoMode
    }

    // MARK: - Endpoints

    /// `GET /v1/auth/me` — returns the operator profile derived from the
    /// bearer token claims.
    public func fetchMe() async throws -> OperatorMe {
        if await usesDemoData { return DemoData.operatorProfile }
        try await get("/v1/auth/me")
    }

    /// `GET /v1/stats/summary` — booth health + queue counts. Operator
    /// caches this for 5s, so 15-minute widget polling is cheap.
    public func fetchStatsSummary() async throws -> StatsSummary {
        if await usesDemoData { return DemoData.statsSummary }
        try await get("/v1/stats/summary")
    }

    /// `GET /v1/stats/overview` — historical aggregation (calls, messages,
    /// playbacks, uploads, top questions, hourly) over the chosen window.
    /// Operator caches results for 30s per window key.
    public func fetchStatsOverview(window: StatsWindow = .last7d) async throws -> StatsOverview {
        if await usesDemoData { return DemoData.statsOverview(window: window) }
        try await get(
            "/v1/stats/overview",
            query: [URLQueryItem(name: "window", value: window.rawValue)]
        )
    }

    /// `GET /v1/status` — current booth state (no auth required, but we
    /// still send the bearer if available so the operator can correlate
    /// access in logs).
    public func fetchBoothStatus() async throws -> BoothStatus {
        if await usesDemoData { return DemoData.boothStatus }
        try await get("/v1/status", requireAuth: false)
    }

    /// `GET /v1/status/history` — recent booth status snapshots used to
    /// render the uptime chart. `since` is optional; default `limit` is
    /// 100 (server caps at 500).
    public func fetchStatusHistory(since: Date? = nil, limit: Int = 100) async throws -> StatusHistory {
        if await usesDemoData {
            return StatusHistory(items: Array(DemoData.statusHistory.prefix(limit)))
        }
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
        if await usesDemoData {
            return SessionListPage(items: Array(DemoData.sessions.prefix(limit)), nextCursor: nil)
        }
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let boothId { items.append(URLQueryItem(name: "boothId", value: boothId)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get("/v1/sessions", query: items)
    }

    /// `GET /v1/sessions/{id}` — one session with its ordered events.
    public func fetchSession(id: String) async throws -> CallSessionDetail {
        if await usesDemoData { return DemoData.sessionDetail(id: id) }
        try await get("/v1/sessions/\(id)")
    }

    /// `GET /v1/system/current?boothId=…` — latest cached system snapshot
    /// for a single booth, unwrapped from its `{boothId, snapshot, receivedAt}`
    /// envelope. When `boothId` is nil, the operator returns the full list
    /// of cached snapshots and this helper picks the first one (typical
    /// single-booth install). Returns `nil` when no snapshot is cached
    /// (operator responds 404 in that case, or returns an empty list).
    public func fetchCurrentSystem(boothId: String? = nil) async throws -> BoothSystemSnapshot? {
        if await usesDemoData { return DemoData.systemEnvelope.snapshot }
        let envelope = try await fetchCurrentSystemEnvelope(boothId: boothId)
        return envelope?.snapshot
    }

    /// Same as `fetchCurrentSystem` but preserves the `receivedAt` server
    /// timestamp from the envelope so the UI can render "Updated 5s ago"
    /// without inventing its own clock.
    public func fetchCurrentSystemEnvelope(
        boothId: String? = nil
    ) async throws -> BoothSystemSnapshotEnvelope? {
        if await usesDemoData { return DemoData.systemEnvelope }
        if let boothId {
            let items = [URLQueryItem(name: "boothId", value: boothId)]
            do {
                return try await get("/v1/system/current", query: items)
            } catch let OperatorError.httpError(status, _) where status == 404 {
                return nil
            }
        }
        // No filter → operator returns `{ items: [Envelope] }`. Pick the
        // first booth for the typical single-booth install.
        let envelopes = try await fetchAllCurrentSystems()
        return envelopes.first
    }

    /// `GET /v1/system/current` (no booth filter) — list of latest cached
    /// snapshots across every booth that's ever reported in. Each item is
    /// a `BoothSystemSnapshotEnvelope`.
    public func fetchAllCurrentSystems() async throws -> [BoothSystemSnapshotEnvelope] {
        if await usesDemoData { return [DemoData.systemEnvelope] }
        let list: BoothSystemSnapshotList = try await get("/v1/system/current")
        return list.items
    }

    /// `GET /v1/messages` — list (filterable by status, since, limit).
    public func fetchMessages(
        status: MessageStatus? = nil,
        since: Date? = nil,
        limit: Int = 50
    ) async throws -> MessageList {
        if await usesDemoData {
            let messages = DemoData.messages.filter { message in
                status == nil || message.status == status
            }
            return MessageList(items: Array(messages.prefix(limit)))
        }
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
        if await usesDemoData { return DemoData.message(id: id) }
        try await get("/v1/messages/\(id)")
    }

    /// `GET /v1/messages/{id}/transcriptions` — every transcription
    /// attempt for the message, newest first.
    public func fetchTranscriptions(messageId: String) async throws -> TranscriptionList {
        if await usesDemoData {
            return TranscriptionList(items: DemoData.transcriptions(messageId: messageId))
        }
        try await get("/v1/messages/\(messageId)/transcriptions")
    }

    /// `POST /v1/messages/{id}/transcribe` — re-runs transcription (and
    /// downstream moderation). Returns the new `Transcription`.
    public func transcribeMessage(id: String) async throws -> Transcription {
        if await usesDemoData { return DemoData.transcriptions(messageId: id).first ?? DemoData.transcription }
        try await postEmpty("/v1/messages/\(id)/transcribe")
    }

    /// `POST /v1/messages/{id}/moderate` — re-runs AI moderation against
    /// the latest succeeded transcription. Returns the new `Moderation`.
    public func moderateMessage(id: String) async throws -> Moderation {
        if await usesDemoData { return DemoData.moderation(messageId: id) }
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
        if await usesDemoData {
            return EventList(items: Array(DemoData.events.prefix(limit)), nextCursor: nil)
        }
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
        if await usesDemoData {
            return QuestionList(items: Array(DemoData.questions.prefix(limit)), nextCursor: nil)
        }
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get("/v1/questions", query: items)
    }

    /// `DELETE /v1/questions/{id}` — soft-deletes (retires) a question.
    public func deleteQuestion(id: String) async throws {
        if await usesDemoData { return }
        try await delete("/v1/questions/\(id)")
    }

    // MARK: - Mobile device registry

    /// `GET /v1/devices` — the caller's active mobile devices.
    public func fetchDevices() async throws -> [MobileDevice] {
        if await usesDemoData { return [] }
        try await get("/v1/devices")
    }

    /// `POST /v1/devices` — register or refresh the APNs token. Server
    /// upserts on `(apnsToken, platform)` so calling this on every launch
    /// (after permission is granted) is the intended flow.
    public func registerDevice(_ body: RegisterMobileDeviceRequest) async throws -> MobileDevice {
        if await usesDemoData { throw OperatorError.unauthenticated }
        try await postJSON("/v1/devices", body: body)
    }

    /// `PATCH /v1/devices/{id}` — push a new preference set or device name
    /// to the server. Returns the merged record.
    public func updateDevice(
        id: String,
        body: UpdateMobileDevicePreferencesRequest
    ) async throws -> MobileDevice {
        if await usesDemoData { throw OperatorError.unauthenticated }
        try await request(method: "PATCH", path: "/v1/devices/\(id)", body: body, requireAuth: true)
    }

    /// `DELETE /v1/devices/{id}` — revoke a device. The server sets
    /// `revokedAt` so APNs delivery to that token stops immediately.
    public func revokeDevice(id: String) async throws {
        if await usesDemoData { return }
        try await delete("/v1/devices/\(id)")
    }

    // MARK: - Core request helpers

    private var usesDemoData: Bool {
        get async {
            if demoMode { return true }
            return await config.isDemoMode
        }
    }

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

        let (data, http) = try await send(request, retryOnUnauthorized: true, path: path)
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

        var attachedBearer = false
        let hasAccessToken = await auth.getAccessToken() != nil
        if requireAuth || hasAccessToken {
            guard let header = await auth.authorizationHeader() else {
                if requireAuth { throw OperatorError.unauthenticated }
                // Optional auth and no token available — proceed unauthenticated.
                return try await perform(request, retryOnUnauthorized: false, path: path)
            }
            request.setValue(header, forHTTPHeaderField: "Authorization")
            attachedBearer = true
        }

        return try await perform(request, retryOnUnauthorized: attachedBearer, path: path)
    }

    private func perform<Response: Decodable>(
        _ request: URLRequest,
        retryOnUnauthorized: Bool,
        path: String
    ) async throws -> Response {
        let (data, http) = try await send(request, retryOnUnauthorized: retryOnUnauthorized, path: path)

        if http.statusCode == 401 || http.statusCode == 403 {
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.warning("\(path, privacy: .public) → \(http.statusCode) body=\(body, privacy: .public)")
            throw OperatorError.unauthorized(body)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.warning("\(path, privacy: .public) → HTTP \(http.statusCode) body=\(body, privacy: .public)")
            throw OperatorError.httpError(status: http.statusCode, body: body)
        }

        do {
            return try OperatorJSON.decoder.decode(Response.self, from: data)
        } catch {
            let preview = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>"
            logger.error("""
                \(path, privacy: .public) decode failed: \
                \(String(describing: error), privacy: .public) \
                body-preview=\(preview, privacy: .public)
                """)
            throw OperatorError.decoding(error)
        }
    }

    /// Sends `request` over `session`. If the response is 401 and the
    /// caller attached a bearer (`retryOnUnauthorized == true`), forces a
    /// token refresh and reissues the request exactly once with the new
    /// bearer header. This makes the client resilient to access tokens
    /// that expired between our proactive refresh check and the actual
    /// HTTP call (clock skew, long-running uploads, or the operator
    /// rotating signing keys). Refresh-token rejection is handled inside
    /// `AuthManager.refreshTokenIfNeeded()` — it signs the user out, and
    /// the retry simply surfaces the original 401.
    private func send(
        _ request: URLRequest,
        retryOnUnauthorized: Bool,
        path: String
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, http) = try await transport(request)
        guard retryOnUnauthorized, http.statusCode == 401 else {
            return (data, http)
        }
        logger.info("\(path, privacy: .public) → 401, refreshing token and retrying once")
        let refreshed = await auth.refreshTokenIfNeeded()
        guard refreshed, let header = await auth.authorizationHeader() else {
            return (data, http)
        }
        var retried = request
        retried.setValue(header, forHTTPHeaderField: "Authorization")
        return try await transport(retried)
    }

    private func transport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let method = request.httpMethod ?? "GET"
        let urlString = request.url?.absoluteString ?? "<nil>"
        let hasAuth = request.value(forHTTPHeaderField: "Authorization") != nil
        let start = Date()
        logger.debug("→ \(method, privacy: .public) \(urlString, privacy: .public) auth=\(hasAuth)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            if let urlError = error as? URLError {
                logger.error("""
                    ✗ \(method, privacy: .public) \(urlString, privacy: .public) \
                    URLError code=\(urlError.code.rawValue) \
                    (\(urlError.localizedDescription, privacy: .public)) \
                    after \(elapsedMs)ms
                    """)
            } else {
                logger.error("""
                    ✗ \(method, privacy: .public) \(urlString, privacy: .public) \
                    transport error: \(String(describing: error), privacy: .public) \
                    after \(elapsedMs)ms
                    """)
            }
            throw OperatorError.transport(error)
        }
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        guard let http = response as? HTTPURLResponse else {
            logger.error("✗ \(method, privacy: .public) \(urlString, privacy: .public) non-HTTP response")
            throw OperatorError.transport(URLError(.badServerResponse))
        }
        logger.debug("""
            ← \(method, privacy: .public) \(urlString, privacy: .public) \
            \(http.statusCode) \(data.count)B in \(elapsedMs)ms
            """)
        return (data, http)
    }
}
