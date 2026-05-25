//
//  IDTokenValidator.swift
//  TelephoneBoothOperatorMobile
//
//  Local validation of OIDC ID-token claims. Per OIDC Core §3.1.3.7, when
//  the ID token is received directly from the token endpoint over TLS,
//  signature verification against JWKS MAY be omitted. We validate claims
//  only: issuer, audience, expiration (with clock skew), and nonce.
//

import Foundation
import os

private let logger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "IDTokenValidator"
)

/// Validates ID-token claims without signature verification.
///
/// This is appropriate for a public PKCE client receiving the token directly
/// from the token endpoint over TLS (OIDC Core §3.1.3.7). The backend still
/// validates access tokens independently.
public struct IDTokenValidator: Sendable {
    /// Maximum acceptable clock skew between device and issuer.
    public static let defaultClockSkew: TimeInterval = 300 // 5 minutes

    /// Decoded claims from an ID token's payload segment.
    struct IDTokenClaims: Decodable {
        let iss: String?
        let aud: AudienceClaim?
        let exp: Double?
        let nonce: String?

        /// `aud` can be a single string or an array of strings.
        enum AudienceClaim: Decodable {
            case single(String)
            case multiple([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let array = try? container.decode([String].self) {
                    self = .multiple(array)
                } else if let string = try? container.decode(String.self) {
                    self = .single(string)
                } else {
                    throw DecodingError.typeMismatch(
                        AudienceClaim.self,
                        .init(codingPath: decoder.codingPath,
                              debugDescription: "aud must be a string or array of strings")
                    )
                }
            }

            func contains(_ clientID: String) -> Bool {
                switch self {
                case .single(let value): return value == clientID
                case .multiple(let values): return values.contains(clientID)
                }
            }
        }
    }

    /// Validates claims in the given ID token JWT.
    ///
    /// - Parameters:
    ///   - idToken: The raw JWT string (three dot-separated base64url segments).
    ///   - expectedNonce: The nonce that was sent in the authorization request.
    ///   - issuer: The expected issuer URL (oidcIssuerBase from AppConfig).
    ///   - clientID: The expected audience / client ID.
    ///   - clockSkew: Acceptable clock skew for expiration check.
    /// - Throws: `AuthError.idTokenValidationFailed` if any claim is invalid.
    public static func validate(
        idToken: String,
        expectedNonce: String,
        issuer: String,
        clientID: String,
        clockSkew: TimeInterval = defaultClockSkew
    ) throws {
        let claims = try decodeClaims(from: idToken)

        // Issuer
        guard let iss = claims.iss else {
            throw AuthError.idTokenValidationFailed("ID token missing 'iss' claim")
        }
        let normalizedIss = iss.hasSuffix("/") ? String(iss.dropLast()) : iss
        let normalizedExpected = issuer.hasSuffix("/") ? String(issuer.dropLast()) : issuer
        guard normalizedIss == normalizedExpected else {
            logger.error("ID token issuer mismatch: got \(iss, privacy: .public)")
            throw AuthError.idTokenValidationFailed(
                "Issuer mismatch: expected \(normalizedExpected), got \(normalizedIss)"
            )
        }

        // Audience
        guard let aud = claims.aud else {
            throw AuthError.idTokenValidationFailed("ID token missing 'aud' claim")
        }
        guard aud.contains(clientID) else {
            logger.error("ID token audience does not contain our client ID")
            throw AuthError.idTokenValidationFailed(
                "Audience does not contain expected client ID"
            )
        }

        // Expiration
        guard let exp = claims.exp else {
            throw AuthError.idTokenValidationFailed("ID token missing 'exp' claim")
        }
        let expirationDate = Date(timeIntervalSince1970: exp)
        let now = Date()
        guard now.addingTimeInterval(-clockSkew) < expirationDate else {
            logger.error("ID token expired at \(expirationDate)")
            throw AuthError.idTokenValidationFailed("ID token has expired")
        }

        // Nonce
        guard let tokenNonce = claims.nonce else {
            throw AuthError.idTokenValidationFailed("ID token missing 'nonce' claim")
        }
        guard tokenNonce == expectedNonce else {
            logger.error("ID token nonce mismatch")
            throw AuthError.idTokenValidationFailed("Nonce mismatch")
        }

        logger.debug("ID token claims validated successfully")
    }

    // MARK: - Private

    static func decodeClaims(from jwt: String) throws -> IDTokenClaims {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else {
            throw AuthError.idTokenValidationFailed(
                "Malformed JWT: expected 3 segments, got \(segments.count)"
            )
        }

        let payloadSegment = String(segments[1])
        guard let payloadData = base64URLDecode(payloadSegment) else {
            throw AuthError.idTokenValidationFailed("Failed to decode JWT payload")
        }

        do {
            return try JSONDecoder().decode(IDTokenClaims.self, from: payloadData)
        } catch {
            throw AuthError.idTokenValidationFailed(
                "Failed to parse ID token claims: \(error.localizedDescription)"
            )
        }
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(contentsOf: String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}
