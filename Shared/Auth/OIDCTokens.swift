//
//  OIDCTokens.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

/// Token bundle returned by Authentik's `/token` endpoint.
public struct OIDCTokens: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let expiresIn: Int?
    public let tokenType: String?

    public enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}
