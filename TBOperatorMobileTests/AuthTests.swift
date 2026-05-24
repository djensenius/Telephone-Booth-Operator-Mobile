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
}
