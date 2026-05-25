//
//  IDTokenValidatorTests.swift
//

import XCTest
@testable import TBOperatorMobile

final class IDTokenValidatorTests: XCTestCase {

    // MARK: - Test helpers

    /// Creates a minimal JWT with the given claims payload (no signature verification needed).
    private func makeJWT(claims: [String: Any]) -> String {
        let header = Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8).base64URLEncoded()
        let payloadData = try! JSONSerialization.data(withJSONObject: claims)
        let payload = payloadData.base64URLEncoded()
        let signature = Data("fake-signature".utf8).base64URLEncoded()
        return "\(header).\(payload).\(signature)"
    }

    private let testIssuer = "https://auth.fluxhaus.io/application/o/telephone-booth-operator-mobile"
    private let testClientID = "telephone-booth-operator-mobile"
    private let testNonce = "test-nonce-abc123"

    private func validClaims(
        iss: String? = nil,
        aud: Any? = nil,
        exp: Double? = nil,
        nonce: String? = nil
    ) -> [String: Any] {
        var claims: [String: Any] = [:]
        claims["iss"] = iss ?? testIssuer
        claims["aud"] = aud ?? testClientID
        claims["exp"] = exp ?? Date().addingTimeInterval(3600).timeIntervalSince1970
        claims["nonce"] = nonce ?? testNonce
        claims["sub"] = "user-123"
        claims["iat"] = Date().timeIntervalSince1970
        return claims
    }

    // MARK: - Tests

    func testValidTokenPassesValidation() throws {
        let jwt = makeJWT(claims: validClaims())
        XCTAssertNoThrow(try IDTokenValidator.validate(
            idToken: jwt,
            expectedNonce: testNonce,
            issuer: testIssuer,
            clientID: testClientID
        ))
    }

    func testValidTokenWithTrailingSlashIssuer() throws {
        let jwt = makeJWT(claims: validClaims(iss: testIssuer + "/"))
        XCTAssertNoThrow(try IDTokenValidator.validate(
            idToken: jwt,
            expectedNonce: testNonce,
            issuer: testIssuer,
            clientID: testClientID
        ))
    }

    func testValidTokenWithArrayAudience() throws {
        let jwt = makeJWT(claims: validClaims(aud: [testClientID, "other-client"]))
        XCTAssertNoThrow(try IDTokenValidator.validate(
            idToken: jwt,
            expectedNonce: testNonce,
            issuer: testIssuer,
            clientID: testClientID
        ))
    }

    func testWrongIssuerThrows() {
        let jwt = makeJWT(claims: validClaims(iss: "https://evil.example.com"))
        XCTAssertThrowsError(try IDTokenValidator.validate(
            idToken: jwt,
            expectedNonce: testNonce,
            issuer: testIssuer,
            clientID: testClientID
        )) { error in
            guard case AuthError.idTokenValidationFailed(let reason) = error else {
                XCTFail("Expected idTokenValidationFailed, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("Issuer mismatch"))
        }
    }

    func testWrongAudienceThrows() {
        let jwt = makeJWT(claims: validClaims(aud: "wrong-client-id"))
        XCTAssertThrowsError(try IDTokenValidator.validate(
            idToken: jwt,
            expectedNonce: testNonce,
            issuer: testIssuer,
            clientID: testClientID
        )) { error in
            guard case AuthError.idTokenValidationFailed(let reason) = error else {
                XCTFail("Expected idTokenValidationFailed, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("Audience"))
        }
    }

    func testExpiredTokenThrows() {
        let expiredExp = Date().addingTimeInterval(-600).timeIntervalSince1970
        let jwt = makeJWT(claims: validClaims(exp: expiredExp))
        XCTAssertThrowsError(try IDTokenValidator.validate(
            idToken: jwt,
            expectedNonce: testNonce,
            issuer: testIssuer,
            clientID: testClientID
        )) { error in
            guard case AuthError.idTokenValidationFailed(let reason) = error else {
                XCTFail("Expected idTokenValidationFailed, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("expired"))
        }
    }

    func testTokenWithinClockSkewPasses() throws {
        // Token expired 2 minutes ago — within 5-minute skew tolerance
        let recentlyExpired = Date().addingTimeInterval(-120).timeIntervalSince1970
        let jwt = makeJWT(claims: validClaims(exp: recentlyExpired))
        XCTAssertNoThrow(try IDTokenValidator.validate(
            idToken: jwt,
            expectedNonce: testNonce,
            issuer: testIssuer,
            clientID: testClientID
        ))
    }

    func testWrongNonceThrows() {
        let jwt = makeJWT(claims: validClaims(nonce: "wrong-nonce"))
        XCTAssertThrowsError(try IDTokenValidator.validate(
            idToken: jwt,
            expectedNonce: testNonce,
            issuer: testIssuer,
            clientID: testClientID
        )) { error in
            guard case AuthError.idTokenValidationFailed(let reason) = error else {
                XCTFail("Expected idTokenValidationFailed, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("Nonce"))
        }
    }

    func testMalformedJWTThrows() {
        XCTAssertThrowsError(try IDTokenValidator.validate(
            idToken: "not-a-jwt",
            expectedNonce: testNonce,
            issuer: testIssuer,
            clientID: testClientID
        )) { error in
            guard case AuthError.idTokenValidationFailed(let reason) = error else {
                XCTFail("Expected idTokenValidationFailed, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("Malformed JWT"))
        }
    }

    func testMissingIssuerClaimThrows() {
        var claims = validClaims()
        claims.removeValue(forKey: "iss")
        let jwt = makeJWT(claims: claims)
        XCTAssertThrowsError(try IDTokenValidator.validate(
            idToken: jwt,
            expectedNonce: testNonce,
            issuer: testIssuer,
            clientID: testClientID
        )) { error in
            guard case AuthError.idTokenValidationFailed(let reason) = error else {
                XCTFail("Expected idTokenValidationFailed, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("iss"))
        }
    }

    func testMissingNonceClaimThrows() {
        var claims = validClaims()
        claims.removeValue(forKey: "nonce")
        let jwt = makeJWT(claims: claims)
        XCTAssertThrowsError(try IDTokenValidator.validate(
            idToken: jwt,
            expectedNonce: testNonce,
            issuer: testIssuer,
            clientID: testClientID
        )) { error in
            guard case AuthError.idTokenValidationFailed(let reason) = error else {
                XCTFail("Expected idTokenValidationFailed, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("nonce"))
        }
    }
}

// MARK: - Helper extension for test JWT construction

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
