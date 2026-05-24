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
    public static let shared = OperatorClient()

    private let config: AppConfig
    private let auth: AuthManager
    private let session: URLSession

    public init(
        config: AppConfig = .shared,
        auth: AuthManager = .shared,
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

    // MARK: - Core request helpers

    private func get<T: Decodable>(_ path: String, requireAuth: Bool = true) async throws -> T {
        try await request(method: "GET", path: path, body: Optional<Data>.none, requireAuth: requireAuth)
    }

    private func request<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        body: Body?,
        requireAuth: Bool = true
    ) async throws -> Response {
        let url = config.url(forPath: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try OperatorJSON.encoder.encode(body)
            } catch {
                throw OperatorError.decoding(error)
            }
        }

        if requireAuth || auth.getAccessToken() != nil {
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
