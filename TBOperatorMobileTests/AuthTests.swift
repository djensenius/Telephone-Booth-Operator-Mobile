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
    func testStoreTokensSucceedsOnFirstWrite() {
        let manager = AuthManager.shared
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
        let manager = AuthManager.shared
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
        let manager = AuthManager.shared
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
    func testKeychainWriteFailedErrorHasDescription() {
        let error = AuthError.keychainWriteFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("credentials") == true)
    }

    // MARK: - Launch validation (validateSessionOnLaunch)

    /// Expired token + transient refresh failure → must sign out, not stay signed in.
    @MainActor
    func testValidateSessionExpiredTokenTransientFailureSignsOut() async {
        let manager = AuthManager.shared
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

        XCTAssertEqual(manager.authState, .signedOut,
                       "Expired token + transient refresh failure must not become .signedIn")
        // Clean up
        manager.urlSession = .shared
        manager.signOut()
    }

    /// Expired token + successful refresh → should sign in.
    @MainActor
    func testValidateSessionExpiredTokenSuccessfulRefreshSignsIn() async {
        let manager = AuthManager.shared
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
        let manager = AuthManager.shared
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
        let manager = AuthManager.shared
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
        let manager = AuthManager.shared
        let tokens = OIDCTokens(
            accessToken: "thisdevice-access-\(UUID().uuidString)",
            refreshToken: "thisdevice-refresh-\(UUID().uuidString)",
            idToken: nil,
            expiresIn: 3600,
            tokenType: "Bearer"
        )
        manager.storeTokens(tokens)

        // Read back the accessibility attribute for the access token
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.davidjensenius.TelephoneBoothOperatorMobile.oidc",
            kSecAttrAccount as String: "oidc_access_token",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        XCTAssertEqual(status, noErr)
        guard let attrs = item as? [String: Any] else {
            XCTFail("Expected dictionary attributes from keychain query")
            manager.signOut()
            return
        }
        let accessible = attrs[kSecAttrAccessible as String] as? String
        XCTAssertEqual(
            accessible,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
            "Token should use AfterFirstUnlockThisDeviceOnly accessibility"
        )
        manager.signOut()
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
