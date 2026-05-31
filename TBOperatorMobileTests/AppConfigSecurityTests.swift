//
//  AppConfigSecurityTests.swift
//  TBOperatorMobileTests
//
//  Tests for hardened API base URL validation (issue #14).
//

import XCTest
@testable import TBOperatorMobile

@MainActor
final class AppConfigSecurityTests: XCTestCase {

    // MARK: - Valid URLs

    func testAcceptsValidHTTPSURL() throws {
        let config = AppConfig.shared
        let original = config.apiBaseURL
        defer { config.apiBaseURL = original }

        XCTAssertNoThrow(try config.setAPIBase("https://api.telephonebooth.io"))
    }

    #if DEBUG
    func testAcceptsHTTPInDebug() throws {
        let config = AppConfig.shared
        let original = config.apiBaseURL
        defer { config.apiBaseURL = original }

        XCTAssertNoThrow(try config.setAPIBase("http://localhost:3001"))
    }
    #endif

    func testNormalisesTrailingSlash() throws {
        let config = AppConfig.shared
        let original = config.apiBaseURL
        defer { config.apiBaseURL = original }

        try config.setAPIBase("https://api.telephonebooth.io///")
        XCTAssertEqual(config.apiBaseURL.absoluteString, "https://api.telephonebooth.io")
    }

    // MARK: - Rejected URLs

    func testRejectsEmptyString() {
        XCTAssertThrowsError(try AppConfig.shared.setAPIBase("")) { error in
            XCTAssertEqual(error as? AppConfigError, .invalidURL)
        }
    }

    func testRejectsURLWithUserinfo() {
        XCTAssertThrowsError(try AppConfig.shared.setAPIBase("https://user:pass@evil.example.com")) { error in
            guard case .unsafeURLComponent = error as? AppConfigError else {
                XCTFail("Expected unsafeURLComponent, got \(error)")
                return
            }
        }
    }

    func testRejectsURLWithQueryParameters() {
        XCTAssertThrowsError(try AppConfig.shared.setAPIBase("https://api.telephonebooth.io?token=abc")) { error in
            guard case .unsafeURLComponent = error as? AppConfigError else {
                XCTFail("Expected unsafeURLComponent, got \(error)")
                return
            }
        }
    }

    func testRejectsURLWithFragment() {
        XCTAssertThrowsError(try AppConfig.shared.setAPIBase("https://api.telephonebooth.io#leak")) { error in
            guard case .unsafeURLComponent = error as? AppConfigError else {
                XCTFail("Expected unsafeURLComponent, got \(error)")
                return
            }
        }
    }

    func testRejectsFTPScheme() {
        XCTAssertThrowsError(try AppConfig.shared.setAPIBase("ftp://files.example.com")) { error in
            XCTAssertEqual(error as? AppConfigError, .invalidURL)
        }
    }

    func testRejectsURLWithoutHost() {
        XCTAssertThrowsError(try AppConfig.shared.setAPIBase("https://")) { error in
            XCTAssertEqual(error as? AppConfigError, .invalidURL)
        }
    }

    // MARK: - Host change detection

    func testReturnsTrueWhenHostChanges() throws {
        let config = AppConfig.shared
        let original = config.apiBaseURL
        defer { config.apiBaseURL = original }

        // Set to a known host first
        try config.setAPIBase("https://api.telephonebooth.io")
        // Change to a different (trusted) host — in DEBUG, allowlist is skipped
        #if DEBUG
        let changed = try config.setAPIBase("https://staging.fluxhaus.io")
        XCTAssertTrue(changed, "Expected host-change flag to be true")
        #endif
    }

    func testReturnsFalseWhenHostSame() throws {
        let config = AppConfig.shared
        let original = config.apiBaseURL
        defer { config.apiBaseURL = original }

        try config.setAPIBase("https://api.telephonebooth.io")
        let changed = try config.setAPIBase("https://api.telephonebooth.io/")
        XCTAssertFalse(changed, "Same host should not flag as changed")
    }

    // MARK: - DEBUG-only tests for private IP blocking logic

    #if DEBUG
    func testIsPrivateOrLoopbackDetectsLocalhost() throws {
        let config = AppConfig.shared
        let original = config.apiBaseURL
        defer { config.apiBaseURL = original }

        // In DEBUG builds we allow these, but the function should still identify them.
        // We test indirectly: in DEBUG, localhost is allowed so setAPIBase succeeds.
        XCTAssertNoThrow(try config.setAPIBase("http://127.0.0.1:8080"))
        XCTAssertNoThrow(try config.setAPIBase("http://localhost:3000"))
    }
    #endif
}

// MARK: - Equatable conformance for test assertions

extension AppConfigError: Equatable {
    public static func == (lhs: AppConfigError, rhs: AppConfigError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL): return true
        case (.httpsRequired, .httpsRequired): return true
        case (.unsafeHost, .unsafeHost): return true
        case (.unsafeURLComponent(let lhsC), .unsafeURLComponent(let rhsC)):
            return lhsC == rhsC
        case (.untrustedHost(let lhsH), .untrustedHost(let rhsH)):
            return lhsH == rhsH
        default: return false
        }
    }
}
