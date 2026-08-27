//
//  AuthTests.swift
//

import XCTest
@testable import TBOperatorMobile

final class AuthTests: XCTestCase {

    func testDeviceAuthorizationDecodesAuthentikPayload() throws {
        let json = Data("""
        {
          "device_code": "abc.dev.code",
          "user_code": "WDJB-MJHT",
          "verification_uri": "https://auth.fluxhaus.io/application/o/device/",
          "verification_uri_complete": "https://auth.fluxhaus.io/application/o/device/?code=WDJB-MJHT",
          "expires_in": 600,
          "interval": 5
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(DeviceAuthorization.self, from: json)
        XCTAssertEqual(decoded.deviceCode, "abc.dev.code")
        XCTAssertEqual(decoded.userCode, "WDJB-MJHT")
        XCTAssertEqual(decoded.verificationURI.absoluteString,
                       "https://auth.fluxhaus.io/application/o/device/")
        XCTAssertEqual(decoded.verificationURIComplete?.absoluteString,
                       "https://auth.fluxhaus.io/application/o/device/?code=WDJB-MJHT")
        XCTAssertEqual(decoded.expiresIn, 600)
        XCTAssertEqual(decoded.interval, 5)
    }

    func testDeviceAuthorizationDecodesWithoutCompleteURI() throws {
        let json = Data("""
        {
          "device_code": "abc.dev.code",
          "user_code": "WDJB-MJHT",
          "verification_uri": "https://auth.fluxhaus.io/application/o/device/",
          "expires_in": 600,
          "interval": 5
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(DeviceAuthorization.self, from: json)
        XCTAssertNil(decoded.verificationURIComplete)
    }

    // MARK: - Token persistence (storeTokens)

    @MainActor
    func testOIDCEndpointsCarryTrailingSlash() {
        // Authentik's global OAuth endpoints strict-match on the trailing slash;
        // `appendingPathComponent` without `isDirectory: true` would 404.
        let manager = makeAuthManager()
        XCTAssertTrue(manager.tokenURL.absoluteString.hasSuffix("/token/"),
                      "tokenURL must carry trailing slash, got \(manager.tokenURL)")
        XCTAssertTrue(manager.deviceAuthorizationURL.absoluteString.hasSuffix("/device/"),
                      "deviceAuthorizationURL must carry trailing slash, got \(manager.deviceAuthorizationURL)")
    }

    @MainActor
    func testStoreTokensSucceedsOnFirstWrite() {
        let manager = makeAuthManager()
        let tokens = OIDCTokens(
            accessToken: "test-access-\(UUID().uuidString)",
            refreshToken: "test-refresh-\(UUID().uuidString)",
            idToken: nil,
            expiresIn: 3600,
            tokenType: "Bearer"
        )
        let result = manager.storeTokens(tokens)
        XCTAssertTrue(result, "storeTokens should succeed with a valid token bundle")
        // Clean up
        manager.signOut()
    }

    @MainActor
    func testStoreTokensUpdateOverwritesExisting() {
        let manager = makeAuthManager()
        let first = OIDCTokens(
            accessToken: "first-access-\(UUID().uuidString)",
            refreshToken: "first-refresh-\(UUID().uuidString)",
            idToken: nil,
            expiresIn: 3600,
            tokenType: "Bearer"
        )
        let second = OIDCTokens(
            accessToken: "second-access-\(UUID().uuidString)",
            refreshToken: "second-refresh-\(UUID().uuidString)",
            idToken: nil,
            expiresIn: 7200,
            tokenType: "Bearer"
        )
        _ = manager.storeTokens(first)
        let result = manager.storeTokens(second)
        XCTAssertTrue(result, "storeTokens should succeed on update (overwrite)")
        XCTAssertEqual(manager.getAccessToken(), second.accessToken)
        manager.signOut()
    }

    @MainActor
    func testStoreTokensReturnsTrueWithoutRefreshToken() {
        let manager = makeAuthManager()
        let tokens = OIDCTokens(
            accessToken: "access-only-\(UUID().uuidString)",
            refreshToken: nil,
            idToken: nil,
            expiresIn: 3600,
            tokenType: "Bearer"
        )
        let result = manager.storeTokens(tokens)
        XCTAssertTrue(result, "storeTokens should succeed when no refresh token provided")
        manager.signOut()
    }

    @MainActor
    func testPrepareWidgetRefreshRestoresUsableCachedSession() async throws {
        let manager = makeAuthManager()
        let stored = manager.storeTokens(
            OIDCTokens(
                accessToken: "widget-access-\(UUID().uuidString)",
                refreshToken: "widget-refresh-\(UUID().uuidString)",
                idToken: nil,
                expiresIn: 3_600,
                tokenType: "Bearer"
            )
        )
        XCTAssertTrue(stored)
        defer { manager.signOut() }

        manager.authState = .unknown
        manager.sessionRestoreFailed = true

        let prepared = await manager.prepareWidgetRefresh()
        XCTAssertTrue(prepared)
        XCTAssertEqual(manager.authState, .signedIn)
        XCTAssertFalse(manager.sessionRestoreFailed)
    }

    @MainActor
    func testKeychainWriteFailedErrorHasDescription() {
        let error = AuthError.keychainWriteFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("credentials") == true)
    }

    // MARK: - Launch validation (validateSessionOnLaunch)

    /// Expired token + transient refresh failure → keep the session and retry.
    /// Discarding a 30-day refresh token because the device happened to be
    /// offline at launch is what makes an app feel like it logs you out
    /// constantly.
    @MainActor
    func testValidateSessionExpiredTokenTransientFailureKeepsSession() async {
        let manager = makeAuthManager()
        // Store an already-expired token
        let expiredTokens = OIDCTokens(
            accessToken: "expired-access-\(UUID().uuidString)",
            refreshToken: "valid-refresh-\(UUID().uuidString)",
            idToken: nil,
            expiresIn: -10,
            tokenType: "Bearer"
        )
        manager.storeTokens(expiredTokens)
        manager.resetStateForTesting()

        // Use a URLSession that simulates a transient network failure
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransientFailureURLProtocol.self]
        manager.urlSession = URLSession(configuration: config)

        await manager.validateSessionOnLaunch()

        XCTAssertEqual(manager.authState, .unknown,
                       "A transient refresh failure must not resolve the session either way")
        XCTAssertTrue(manager.sessionRestoreFailed,
                      "The UI needs to know the restore failed so it can offer a retry")
        XCTAssertNotNil(manager.getKeychainItem(account: "oidc_refresh_token"),
                        "The refresh token must survive a transient failure")
        // Clean up
        manager.urlSession = .shared
        manager.signOut()
    }

    /// A rate-limited, misconfigured, or unparseable `/token` response is not
    /// a dead session — only a protocol-valid `invalid_grant` is.
    @MainActor
    func testOnlyProtocolValidInvalidGrantIsADefinitiveRejection() {
        XCTAssertFalse(
            AuthManager.isDefinitiveRejection(status: 429, body: Data()),
            "429 means slow down, not signed out"
        )
        XCTAssertFalse(
            AuthManager.isDefinitiveRejection(
                status: 400, body: Data("{\"error\":\"server_error\"}".utf8)
            ),
            "A 400 carrying a non-fatal OAuth error must not clear the session"
        )
        XCTAssertFalse(
            AuthManager.isDefinitiveRejection(status: 403, body: Data("<html>blocked</html>".utf8)),
            "A proxy/WAF 403 must not clear the session"
        )
        XCTAssertFalse(
            AuthManager.isDefinitiveRejection(status: 401, body: Data()),
            "A bare 401 is ambiguous — a proxy produces the same thing"
        )
        XCTAssertFalse(
            AuthManager.isDefinitiveRejection(status: 400, body: Data()),
            "A 400 with no OAuth error payload proves nothing about the grant"
        )
        XCTAssertFalse(
            AuthManager.isDefinitiveRejection(
                status: 400, body: Data("{\"error\":\"invalid_client\"}".utf8)
            ),
            "Client/scope misconfiguration is a provider outage, not a dead grant"
        )
        XCTAssertFalse(
            AuthManager.isDefinitiveRejection(
                status: 500, body: Data("{\"error\":\"invalid_grant\"}".utf8)
            ),
            "invalid_grant only counts on the protocol's 400 response"
        )
        XCTAssertTrue(
            AuthManager.isDefinitiveRejection(
                status: 400, body: Data("{\"error\":\"invalid_grant\"}".utf8)
            ),
            "invalid_grant means the refresh token is dead"
        )
    }

    /// Expired token + successful refresh → should sign in.
    @MainActor
    func testValidateSessionExpiredTokenSuccessfulRefreshSignsIn() async {
        let manager = makeAuthManager()
        // Store an already-expired token with a refresh token
        let expiredTokens = OIDCTokens(
            accessToken: "expired-access-\(UUID().uuidString)",
            refreshToken: "good-refresh-\(UUID().uuidString)",
            idToken: nil,
            expiresIn: -10,
            tokenType: "Bearer"
        )
        manager.storeTokens(expiredTokens)
        manager.resetStateForTesting()

        // Use a URLSession that returns a successful token response
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SuccessfulRefreshURLProtocol.self]
        manager.urlSession = URLSession(configuration: config)

        await manager.validateSessionOnLaunch()

        XCTAssertEqual(manager.authState, .signedIn,
                       "Expired token + successful refresh should restore .signedIn")
        // Clean up
        manager.urlSession = .shared
        manager.signOut()
    }

    /// Unexpired token + transient refresh failure → should stay signed in
    /// (the token is still usable).
    @MainActor
    func testValidateSessionUnexpiredTokenTransientFailureStaysSignedIn() async {
        let manager = makeAuthManager()
        // Store a token that expires in the future (but within the "soon" window
        // so refresh is attempted)
        let soonTokens = OIDCTokens(
            accessToken: "valid-access-\(UUID().uuidString)",
            refreshToken: "valid-refresh-\(UUID().uuidString)",
            idToken: nil,
            expiresIn: 30,
            tokenType: "Bearer"
        )
        manager.storeTokens(soonTokens)
        manager.resetStateForTesting()

        // Use a URLSession that simulates a transient network failure
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransientFailureURLProtocol.self]
        manager.urlSession = URLSession(configuration: config)

        await manager.validateSessionOnLaunch()

        XCTAssertEqual(manager.authState, .signedIn,
                       "Unexpired token + transient refresh failure should stay .signedIn")
        // Clean up
        manager.urlSession = .shared
        manager.signOut()
    }

    /// No refresh token at all → should sign out.
    @MainActor
    func testValidateSessionNoRefreshTokenSignsOut() async {
        let manager = makeAuthManager()
        // Store access token only (no refresh token)
        let tokens = OIDCTokens(
            accessToken: "orphan-access-\(UUID().uuidString)",
            refreshToken: nil,
            idToken: nil,
            expiresIn: -10,
            tokenType: "Bearer"
        )
        manager.storeTokens(tokens)
        manager.resetStateForTesting()

        await manager.validateSessionOnLaunch()

        XCTAssertEqual(manager.authState, .signedOut,
                       "No refresh token must result in .signedOut")
        manager.signOut()
    }

    // MARK: - Keychain accessibility migration

    @MainActor
    func testKeychainItemsUseThisDeviceOnlyAccessibility() {
        let keychain = TestKeychainStore()
        let manager = AuthManager(keychainStore: keychain)
        let tokens = OIDCTokens(
            accessToken: "thisdevice-access-\(UUID().uuidString)",
            refreshToken: "thisdevice-refresh-\(UUID().uuidString)",
            idToken: nil,
            expiresIn: 3600,
            tokenType: "Bearer"
        )
        manager.storeTokens(tokens)

        XCTAssertEqual(
            keychain.accessibilityByAccount["oidc_access_token"],
            .afterFirstUnlockThisDeviceOnly,
            "Token should use AfterFirstUnlockThisDeviceOnly accessibility"
        )
        manager.signOut()
    }

    // MARK: - Phone-as-broker (watch handoff)

    @MainActor
    func testBrokerAccessTokenReturnsNilWhenSignedOut() async {
        let manager = makeAuthManager()
        let brokered = await manager.brokerAccessTokenForWatch()
        XCTAssertNil(brokered, "Broker must not vend a token when signed out")
    }

    @MainActor
    func testBrokerAccessTokenVendsCurrentAccessToken() async throws {
        let manager = makeAuthManager()
        let token = "broker-access-\(UUID().uuidString)"
        let stored = manager.storeTokens(OIDCTokens(
            accessToken: token,
            refreshToken: "broker-refresh-\(UUID().uuidString)",
            idToken: nil,
            expiresIn: 3600,
            tokenType: "Bearer"
        ))
        XCTAssertTrue(stored)

        let brokered = await manager.brokerAccessTokenForWatch()
        XCTAssertEqual(brokered?.accessToken, token,
                       "Broker should vend the phone's current access token")
        if let expiry = brokered?.expiry {
            XCTAssertGreaterThan(expiry, Date().timeIntervalSince1970,
                                 "Brokered expiry should be in the future")
        } else {
            XCTFail("Expected a brokered expiry")
        }
        manager.signOut()
    }

    @MainActor
    private func makeAuthManager() -> AuthManager {
        AuthManager(keychainStore: TestKeychainStore())
    }
}

@MainActor
final class TestKeychainStore: KeychainStoring {
    private var values: [String: String] = [:]
    private(set) var accessibilityByAccount: [String: KeychainAccessibility] = [:]

    func migrateAccessibility(
        service: String,
        accounts: [String],
        to accessibility: KeychainAccessibility
    ) {
        for account in accounts where values[key(service: service, account: account)] != nil {
            accessibilityByAccount[account] = accessibility
        }
    }

    func set(
        service: String,
        account: String,
        value: String,
        accessibility: KeychainAccessibility
    ) -> Bool {
        values[key(service: service, account: account)] = value
        accessibilityByAccount[account] = accessibility
        return true
    }

    func get(service: String, account: String) -> String? {
        values[key(service: service, account: account)]
    }

    func delete(service: String, account: String) {
        values.removeValue(forKey: key(service: service, account: account))
        accessibilityByAccount.removeValue(forKey: account)
    }

    private func key(service: String, account: String) -> String {
        "\(service):\(account)"
    }
}

// MARK: - URL Protocol mocks for launch tests

/// Simulates a transient network failure (connection error).
private class TransientFailureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

/// Simulates a successful token refresh response from Authentik.
private class SuccessfulRefreshURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let responseBody = Data("""
        {
            "access_token": "fresh-access-\(UUID().uuidString)",
            "refresh_token": "fresh-refresh-\(UUID().uuidString)",
            "expires_in": 3600,
            "token_type": "Bearer"
        }
        """.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
