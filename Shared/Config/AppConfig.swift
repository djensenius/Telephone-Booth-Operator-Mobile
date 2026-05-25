//
//  AppConfig.swift
//  TelephoneBoothOperatorMobile
//
//  Runtime configuration for the operator API + OIDC. Defaults come from
//  Info.plist (so CI builds and unit tests both pick up safe values).
//  The API base URL can be overridden at runtime via Settings; it persists
//  in UserDefaults so the same URL is used on subsequent launches.
//

import Foundation
import Observation
import os

private let logger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "AppConfig"
)

/// Observable singleton holding mutable app configuration.
///
/// The API base URL is mutable so a user can point their build at a staging
/// or self-hosted operator instance from Settings. OIDC config is static
/// (Info.plist) — changing identity providers at runtime would invalidate
/// stored tokens and is not supported.
@Observable
@MainActor
public final class AppConfig {
    nonisolated(unsafe) public static let shared = AppConfig()

    private static let apiBaseDefaultsKey = "TBOperatorAPIBase"

    /// The configured operator API base URL (no trailing slash).
    /// Falls back to the Info.plist default if no override is stored.
    public var apiBaseURL: URL {
        didSet {
            UserDefaults.standard.set(apiBaseURL.absoluteString, forKey: Self.apiBaseDefaultsKey)
            logger.info("apiBaseURL updated to \(self.apiBaseURL.absoluteString, privacy: .public)")
        }
    }

    /// The OIDC issuer base URL (e.g. https://auth.fluxhaus.io/application/o/telephone-booth-operator-mobile).
    public let oidcIssuerBase: String

    /// The OIDC client ID registered with Authentik as a public, PKCE-only client.
    public let oidcClientID: String

    /// Custom URL scheme used for the OAuth redirect callback (matches the Info.plist URL types entry).
    public let redirectScheme: String = "tboperator"

    /// Full redirect URI registered with Authentik for this app.
    public let redirectURI: String = "tboperator://oauth/callback"

    /// OIDC scopes requested at sign-in time.
    public let oidcScopes: String = "openid email profile offline_access"

    private init() {
        let defaultBaseString = Bundle.main.object(forInfoDictionaryKey: "OperatorAPIBase") as? String
            ?? "https://operator.fluxhaus.io"
        let stored = UserDefaults.standard.string(forKey: Self.apiBaseDefaultsKey)
        let baseString = stored ?? defaultBaseString
        guard let url = URL(string: baseString) else {
            preconditionFailure("AppConfig: invalid API base URL \(baseString)")
        }
        self.apiBaseURL = url

        self.oidcIssuerBase = Bundle.main.object(forInfoDictionaryKey: "OIDCIssuerBase") as? String
            ?? "https://auth.fluxhaus.io/application/o/telephone-booth-operator-mobile"
        self.oidcClientID = Bundle.main.object(forInfoDictionaryKey: "OIDCClientID") as? String
            ?? "telephone-booth-operator-mobile"
        logger.info("Loaded config — apiBase=\(self.apiBaseURL.absoluteString, privacy: .public)")
    }

    /// Update the API base URL. Trailing slashes are normalised away so callers
    /// can paste either form. Throws if the input isn't a valid http(s) URL.
    public func setAPIBase(_ rawString: String) throws {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil
        else {
            throw AppConfigError.invalidURL
        }
        var normalised = trimmed
        while normalised.hasSuffix("/") {
            normalised.removeLast()
        }
        guard let url = URL(string: normalised) else {
            throw AppConfigError.invalidURL
        }
        apiBaseURL = url
    }

    /// Build a fully-qualified URL by appending a `/v1/...` style path
    /// to the configured base.
    public func url(forPath path: String) -> URL {
        var trimmed = path
        if !trimmed.hasPrefix("/") { trimmed = "/" + trimmed }
        return apiBaseURL.appendingPathComponent(String(trimmed.dropFirst()))
    }
}

public enum AppConfigError: Error, LocalizedError {
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a valid https:// URL."
        }
    }
}
