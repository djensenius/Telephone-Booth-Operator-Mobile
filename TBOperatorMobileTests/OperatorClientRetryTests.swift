//
//  OperatorClientRetryTests.swift
//  TBOperatorMobileTests
//
//  Verifies that the operator REST client transparently refreshes its
//  bearer token and retries once when the server returns 401.
//

import XCTest
@testable import TBOperatorMobile

final class OperatorClientRetryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        RetryFlowURLProtocol.reset()
    }

    @MainActor
    func testOperatorClientRefreshesAndRetriesAfter401() async throws {
        let auth = AuthManager.shared
        let seed = OIDCTokens(
            accessToken: "stale-access-\(UUID().uuidString)",
            refreshToken: "valid-refresh-\(UUID().uuidString)",
            idToken: nil,
            expiresIn: 3600,
            tokenType: "Bearer"
        )
        XCTAssertTrue(auth.storeTokens(seed), "seed token write failed")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RetryFlowURLProtocol.self]
        let session = URLSession(configuration: config)
        auth.urlSession = session
        let client = OperatorClient(
            config: AppConfig.shared,
            auth: auth,
            session: session
        )

        let profile = try await client.fetchMe()
        XCTAssertEqual(profile.id, "operator-1")
        XCTAssertEqual(profile.email, "ada@example.com")

        XCTAssertEqual(auth.getAccessToken(), "fresh-access",
                       "Access token must have been refreshed during retry")
        XCTAssertEqual(RetryFlowURLProtocol.meRequestCount, 2,
                       "/v1/auth/me must be hit twice (initial 401 + post-refresh retry)")
        XCTAssertEqual(RetryFlowURLProtocol.tokenRequestCount, 1,
                       "Token endpoint must be hit exactly once for the refresh")

        auth.urlSession = .shared
        auth.signOut()
    }

    @MainActor
    func testOperatorClientSurfaces401WhenRefreshFails() async throws {
        let auth = AuthManager.shared
        let seed = OIDCTokens(
            accessToken: "stale-access-\(UUID().uuidString)",
            refreshToken: "doomed-refresh-\(UUID().uuidString)",
            idToken: nil,
            expiresIn: 3600,
            tokenType: "Bearer"
        )
        XCTAssertTrue(auth.storeTokens(seed))

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailingRefreshURLProtocol.self]
        let session = URLSession(configuration: config)
        auth.urlSession = session
        let client = OperatorClient(
            config: AppConfig.shared,
            auth: auth,
            session: session
        )

        do {
            _ = try await client.fetchMe()
            XCTFail("Expected fetchMe() to throw when refresh also fails")
        } catch let OperatorError.unauthorized(body) {
            XCTAssertTrue(body.contains("token_expired"),
                          "Expected the original 401 body to be surfaced")
        } catch {
            XCTFail("Expected OperatorError.unauthorized, got \(error)")
        }

        // A protocol-valid `invalid_grant` from /token signs the user out via
        // AuthManager.refreshSession().
        XCTAssertEqual(auth.authState, .signedOut,
                       "Refresh-token rejection must sign the user out")

        auth.urlSession = .shared
        auth.signOut()
    }

    /// `/v1/status` became an authenticated endpoint, so a signed-out call
    /// must fail fast with `.unauthenticated` rather than spending a round
    /// trip to collect a generic 401.
    @MainActor
    func testFetchBoothStatusFailsFastWhenSignedOut() async throws {
        let config = AppConfig.shared
        let previousDemoMode = config.isDemoMode
        config.isDemoMode = false
        defer { config.isDemoMode = previousDemoMode }

        let auth = AuthManager.shared
        auth.signOut()
        XCTAssertNil(auth.getAccessToken(), "Precondition: no bearer may be stored")

        UnreachableURLProtocol.reset()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [UnreachableURLProtocol.self]
        let client = OperatorClient(
            config: config,
            auth: auth,
            session: URLSession(configuration: sessionConfig)
        )

        do {
            _ = try await client.fetchBoothStatus()
            XCTFail("Expected fetchBoothStatus() to throw while signed out")
        } catch OperatorError.unauthenticated {
            // Expected.
        } catch {
            XCTFail("Expected OperatorError.unauthenticated, got \(error)")
        }

        XCTAssertEqual(UnreachableURLProtocol.requestCount, 0,
                       "A signed-out status fetch must not reach the network")
    }

    @MainActor
    func testClaimMessageProcessingUsesLeaseEndpointAndContractBody() async throws {
        let auth = AuthManager.shared
        XCTAssertTrue(auth.storeTokens(
            OIDCTokens(
                accessToken: "claim-access-\(UUID().uuidString)",
                refreshToken: "claim-refresh-\(UUID().uuidString)",
                idToken: nil,
                expiresIn: 3600,
                tokenType: "Bearer"
            )
        ))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClaimRequestURLProtocol.self]
        let client = OperatorClient(
            config: .shared,
            auth: auth,
            session: URLSession(configuration: config)
        )
        let claim = try await client.claimMessageProcessing(
            MessageProcessingClaimRequest(capabilities: [.transcription, .review], leaseSeconds: 300)
        )
        XCTAssertEqual(claim?.defaultTranscriptionLanguage, "fr-CA")
        XCTAssertEqual(ClaimRequestURLProtocol.path, "/v1/message-processing/claim")
        let body = try XCTUnwrap(ClaimRequestURLProtocol.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["capabilities"] as? [String], ["transcription", "review"])
        XCTAssertEqual(json?["leaseSeconds"] as? Int, 300)
        auth.signOut()
    }
}

// MARK: - URL protocol mocks

/// Returns 401 on the first `/v1/auth/me`, then 200 after the client
/// successfully exchanges the refresh token at `/token`.
private final class RetryFlowURLProtocol: URLProtocol {
    nonisolated(unsafe) static var meRequestCount = 0
    nonisolated(unsafe) static var tokenRequestCount = 0
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        meRequestCount = 0
        tokenRequestCount = 0
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let path = url.path

        if path.hasSuffix("/token") {
            Self.lock.lock(); Self.tokenRequestCount += 1; Self.lock.unlock()
            let body = Data("""
            {
              "access_token": "fresh-access",
              "refresh_token": "rotated-refresh",
              "expires_in": 3600,
              "token_type": "Bearer"
            }
            """.utf8)
            respond(status: 200, body: body)
            return
        }

        if path.hasSuffix("/v1/auth/me") {
            Self.lock.lock()
            Self.meRequestCount += 1
            let count = Self.meRequestCount
            Self.lock.unlock()

            if count == 1 {
                respond(status: 401,
                        body: Data("{\"error\":\"token_expired\"}".utf8))
                return
            }
            let body = Data("""
            {
              "id": "operator-1",
              "name": "Ada Lovelace",
              "email": "ada@example.com",
              "groups": ["telephone-booth-operators"],
              "picture": null,
              "providerName": "Authentik"
            }
            """.utf8)
            respond(status: 200, body: body)
            return
        }

        respond(status: 404, body: Data())
    }

    private func respond(status: Int, body: Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Fails any request that reaches it, so tests can assert that a code path
/// short-circuits before touching the network.
private final class UnreachableURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        requestCount = 0
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lock.lock(); Self.requestCount += 1; Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
    }
}

/// Always 401 on `/v1/auth/me` and always 400 on `/token` — verifies the
/// client surfaces the original 401 and that the refresh-token rejection
/// signs the user out.
private final class FailingRefreshURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let body: Data
        let status: Int
        if url.path.hasSuffix("/token") {
            status = 400
            body = Data("{\"error\":\"invalid_grant\"}".utf8)
        } else {
            status = 401
            body = Data("{\"error\":\"token_expired\"}".utf8)
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class ClaimRequestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var path: String?
    nonisolated(unsafe) static var body: Data?
    private static let lock = NSLock()

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lock.lock()
        Self.path = request.url?.path
        Self.body = request.httpBody
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let body = Data(#"""
        {
          "claim": {
            "message": {
              "id": "message-1",
              "status": "pending",
              "createdAt": "2026-08-14T12:00:00Z",
              "audio": {
                "url": "https://example.com/audio.flac",
                "sha256": "abc",
                "durationMs": 1200
              }
            },
            "needs": ["transcription"],
            "leaseToken": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "leaseExpiresAt": "2026-08-14T12:05:00Z",
            "defaultTranscriptionLanguage": "fr-CA"
          }
        }
        """#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
