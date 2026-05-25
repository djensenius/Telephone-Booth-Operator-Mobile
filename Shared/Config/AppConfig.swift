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
    public static let shared = AppConfig()

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

    /// Trusted hosts that are allowed as API targets. When non-empty (and
    /// not in a DEBUG build), any host not in this set is rejected.
    public static let trustedHosts: Set<String> = {
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: "TrustedAPIHosts") as? [String],
           !plistValue.isEmpty {
            return Set(plistValue.map { $0.lowercased() })
        }
        return ["operator.fluxhaus.io"]
    }()

    /// Update the API base URL with strict security validation.
    ///
    /// Validation rules:
    /// - Must be a valid URL with an `https` scheme (release) or `http`/`https` (DEBUG).
    /// - Must not contain userinfo, query parameters, or fragments.
    /// - Must not target localhost or private/link-local IPs (release only).
    /// - Must be in the trusted-hosts allowlist if one is configured (release only).
    ///
    /// If the host changes, existing auth tokens are cleared and the user must
    /// re-authenticate against the new server.
    ///
    /// - Returns: `true` if the host changed (tokens were cleared), `false` otherwise.
    @discardableResult
    public func setAPIBase(_ rawString: String) throws -> Bool {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty
        else {
            throw AppConfigError.invalidURL
        }

        // Scheme validation
        #if DEBUG
        guard scheme == "https" || scheme == "http" else {
            throw AppConfigError.invalidURL
        }
        #else
        guard scheme == "https" else {
            throw AppConfigError.httpsRequired
        }
        #endif

        // Reject userinfo, query, and fragments — these have no legitimate use
        // for an API base and could be used to exfiltrate data.
        if components.user != nil || components.password != nil {
            throw AppConfigError.unsafeURLComponent("userinfo")
        }
        if components.query != nil || components.queryItems?.isEmpty == false {
            throw AppConfigError.unsafeURLComponent("query parameters")
        }
        if components.fragment != nil {
            throw AppConfigError.unsafeURLComponent("fragment")
        }

        // Block private/loopback addresses in release builds
        #if !DEBUG
        if Self.isPrivateOrLoopback(host) {
            throw AppConfigError.unsafeHost
        }
        #endif

        // Trusted-host allowlist (release only)
        #if !DEBUG
        if !Self.trustedHosts.isEmpty && !Self.trustedHosts.contains(host) {
            throw AppConfigError.untrustedHost(host)
        }
        #endif

        // Normalise trailing slashes
        var normalised = trimmed
        while normalised.hasSuffix("/") {
            normalised.removeLast()
        }
        guard let url = URL(string: normalised) else {
            throw AppConfigError.invalidURL
        }

        // Detect host change and clear tokens if needed
        let previousHost = apiBaseURL.host?.lowercased()
        let hostChanged = previousHost != host

        apiBaseURL = url

        if hostChanged {
            logger.warning(
                "API host changed from \(previousHost ?? "nil", privacy: .public) " +
                "to \(host, privacy: .public) — clearing auth tokens"
            )
            AuthManager.shared.signOut()
        }

        return hostChanged
    }

    // MARK: - Private Helpers

    /// Returns `true` if the host is a loopback, private, or link-local address.
    private static func isPrivateOrLoopback(_ host: String) -> Bool {
        let loopback = ["localhost", "127.0.0.1", "[::1]", "::1"]
        if loopback.contains(host) { return true }

        // IPv4 private ranges
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        if parts.count == 4 {
            if parts[0] == 10 { return true }                              // 10.0.0.0/8
            if parts[0] == 172 && (16...31).contains(parts[1]) { return true } // 172.16.0.0/12
            if parts[0] == 192 && parts[1] == 168 { return true }          // 192.168.0.0/16
            if parts[0] == 169 && parts[1] == 254 { return true }          // link-local
        }

        return false
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
    case httpsRequired
    case unsafeURLComponent(String)
    case unsafeHost
    case untrustedHost(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid https:// URL."
        case .httpsRequired:
            return "Only secure (https) connections are allowed."
        case .unsafeURLComponent(let component):
            return "URL must not contain \(component)."
        case .unsafeHost:
            return "Private or loopback addresses are not allowed."
        case .untrustedHost(let host):
            return "\(host) is not in the trusted hosts list."
        }
    }
}
