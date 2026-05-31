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

        // Hard-fail refresh (4xx) signs the user out via AuthManager.refreshTokenIfNeeded.
        XCTAssertEqual(auth.authState, .signedOut,
                       "Refresh-token rejection must sign the user out")

        auth.urlSession = .shared
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
