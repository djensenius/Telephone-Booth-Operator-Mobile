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
}
