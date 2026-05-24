//
//  AuthManager.swift
//  TelephoneBoothOperatorMobile
//
//  OIDC Authorization Code + PKCE flow against Authentik. Tokens live in
//  the Keychain. Refresh is serialised through `RefreshCoordinator` so
//  concurrent callers issue at most one network request.
//
//  Compiles on every Apple platform; on tvOS `signInWithOIDC()` throws
//  `.unsupportedPlatform` — Apple TV pairs through a paired iPhone in a
//  later PR.
//

import CryptoKit
import Foundation
import Observation
import os

#if !os(tvOS)
import AuthenticationServices
#endif

private let logger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "AuthManager"
)

/// Serialises concurrent refresh attempts: at most one in-flight refresh
/// per process.
private actor RefreshCoordinator {
    private var isRefreshing = false
    private var continuations: [CheckedContinuation<Bool, Never>] = []

    func acquireOrWait() async -> Bool? {
        if isRefreshing {
            return await withCheckedContinuation { cont in continuations.append(cont) }
        }
        isRefreshing = true
        return nil
    }

    func complete(success: Bool) {
        let waiters = continuations
        continuations.removeAll()
        isRefreshing = false
        for waiter in waiters { waiter.resume(returning: success) }
    }
}

/// OIDC authentication manager for the Telephone-Booth Operator mobile app.
///
/// PKCE-based public-client flow against Authentik. Tokens are kept in the
/// Keychain and refreshed automatically before expiry. The manager is
/// observable; views can read `authState` directly.
@Observable
public final class AuthManager: @unchecked Sendable {
    public static let shared = AuthManager()

    public enum AuthState: Sendable {
        case unknown
        case signedIn
        case signedOut
    }

    public private(set) var authState: AuthState = .unknown
    public var isSignedIn: Bool { authState == .signedIn }

    @ObservationIgnored
    private let config = AppConfig.shared

    #if !os(tvOS)
    @ObservationIgnored
    private var currentSession: ASWebAuthenticationSession?
    #if !os(watchOS)
    @ObservationIgnored
    private var anchorProvider: AuthAnchorProvider?
    #endif
    #endif

    @ObservationIgnored
    private let refreshCoordinator = RefreshCoordinator()

    private init() {
        if getAccessToken() != nil {
            if let expiryStr = getKeychainItem(account: "oidc_token_expiry"),
               let interval = TimeInterval(expiryStr),
               Date() >= Date(timeIntervalSince1970: interval) {
                authState = .unknown
                logger.info("Init: token found but expired, will validate")
            } else {
                authState = .signedIn
                logger.info("Init: signed in (valid token in keychain)")
            }
        } else {
            authState = .signedOut
            logger.info("Init: no token found, signedOut")
        }
    }

    // MARK: - Session lifecycle

    /// Validates the cached session at app launch. On a definitive 4xx
    /// refresh rejection the session is cleared; transient/offline failures
    /// allow the cached token to be used.
    @MainActor public func validateSessionOnLaunch() async {
        guard authState == .unknown else { return }
        guard getKeychainItem(account: "oidc_refresh_token") != nil else {
            logger.info("validateSession: no refresh token — signing out")
            signOut()
            return
        }

        _ = await refreshTokenIfNeeded()
        if authState == .unknown {
            authState = .signedIn
            logger.info("validateSession: session restored")
        }
    }

    /// Returns the `Authorization: Bearer <token>` header, refreshing
    /// proactively if the cached token is near expiry. Returns nil if the
    /// session is invalid.
    public func authorizationHeader() async -> String? {
        guard await ensureValidToken(), let token = getAccessToken() else {
            return nil
        }
        return "Bearer \(token)"
    }

    /// Begins an interactive OIDC sign-in using ASWebAuthenticationSession.
    /// Throws `.unsupportedPlatform` on tvOS.
    @MainActor public func signInWithOIDC() async throws {
        #if os(tvOS)
        throw AuthError.unsupportedPlatform
        #else
        let verifier = Self.generateRandomString()
        let challenge = Self.base64URLEncode(
            Data(SHA256.hash(data: Data(verifier.utf8)))
        )
        let stateNonce = Self.generateRandomString()

        guard var components = URLComponents(string: authorizeURL.absoluteString) else {
            throw AuthError.unknown
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.oidcClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.oidcScopes),
            URLQueryItem(name: "state", value: stateNonce),
            URLQueryItem(name: "nonce", value: Self.generateRandomString()),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authURL = components.url else { throw AuthError.unknown }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: config.redirectScheme
            ) { @Sendable url, error in
                if let asError = error as? ASWebAuthenticationSessionError,
                   asError.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: AuthError.unknown)
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            #if !os(watchOS)
            let provider = AuthAnchorProvider()
            session.presentationContextProvider = provider
            anchorProvider = provider
            #endif
            currentSession = session
            session.start()
        }
        currentSession = nil
        #if !os(watchOS)
        anchorProvider = nil
        #endif

        let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        guard let code = callbackComponents?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.noCode
        }
        let returnedState = callbackComponents?.queryItems?
            .first(where: { $0.name == "state" })?.value
        guard returnedState == stateNonce else {
            logger.error("OIDC state mismatch")
            throw AuthError.stateMismatch
        }

        let tokens = try await exchangeCode(code, verifier: verifier)
        storeTokens(tokens)
        authState = .signedIn
        logger.info("Signed in via OIDC")
        #endif
    }

    @MainActor public func signOut() {
        deleteKeychainItem(account: "oidc_access_token")
        deleteKeychainItem(account: "oidc_refresh_token")
        deleteKeychainItem(account: "oidc_token_expiry")
        authState = .signedOut
        logger.info("Signed out")
    }

    // MARK: - Token storage / refresh

    public func getAccessToken() -> String? {
        getKeychainItem(account: "oidc_access_token")
    }

    public func isTokenExpiringSoon(margin: TimeInterval = 60) -> Bool {
        guard getAccessToken() != nil else { return false }
        guard let expiryStr = getKeychainItem(account: "oidc_token_expiry"),
              let interval = TimeInterval(expiryStr) else { return true }
        return Date().addingTimeInterval(margin) >= Date(timeIntervalSince1970: interval)
    }

    /// Refreshes proactively if near expiry. Returns true if a usable
    /// access token is in the Keychain after the call.
    public func ensureValidToken() async -> Bool {
        await restoreStateIfNeeded()
        guard getAccessToken() != nil else { return false }
        guard isTokenExpiringSoon() else { return true }
        logger.debug("ensureValidToken: refreshing proactively")
        return await refreshTokenIfNeeded()
    }

    @MainActor private func restoreStateIfNeeded() {
        guard authState == .signedOut else { return }
        if getAccessToken() != nil { authState = .signedIn }
    }

    public func refreshTokenIfNeeded() async -> Bool {
        if let coalesced = await refreshCoordinator.acquireOrWait() { return coalesced }
        guard let refreshToken = getKeychainItem(account: "oidc_refresh_token") else {
            logger.warning("refreshTokenIfNeeded: no refresh token")
            await refreshCoordinator.complete(success: false)
            return false
        }
        do {
            let tokens = try await refreshAccessToken(refreshToken)
            storeTokens(tokens)
            logger.info("Token refreshed (expiresIn=\(tokens.expiresIn ?? -1))")
            await refreshCoordinator.complete(success: true)
            return true
        } catch AuthError.refreshTokenInvalid(let reason) {
            logger.error("Refresh token rejected — signing out: \(reason, privacy: .public)")
            await refreshCoordinator.complete(success: false)
            await MainActor.run { signOut() }
            return false
        } catch {
            logger.warning("Refresh failed transiently: \(error.localizedDescription, privacy: .public)")
            await refreshCoordinator.complete(success: false)
            return false
        }
    }

    // MARK: - OIDC endpoint URLs

    private var authorizeURL: URL {
        urlByReplacingFinalSegment("authorize") ?? URL(string: config.oidcIssuerBase + "/authorize/")!
    }

    private var tokenURL: URL {
        urlByReplacingFinalSegment("token") ?? URL(string: config.oidcIssuerBase + "/token/")!
    }

    private func urlByReplacingFinalSegment(_ segment: String) -> URL? {
        guard let base = URL(string: config.oidcIssuerBase) else { return nil }
        return base.deletingLastPathComponent().appendingPathComponent(segment)
    }

    // MARK: - Token network

    private func exchangeCode(_ code: String, verifier: String) async throws -> OIDCTokens {
        let params: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", config.redirectURI),
            ("client_id", config.oidcClientID),
            ("code_verifier", verifier),
            ("scope", config.oidcScopes)
        ]
        let (data, http) = try await postForm(tokenURL, params: params)
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.tokenExchangeFailed(body)
        }
        return try JSONDecoder().decode(OIDCTokens.self, from: data)
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> OIDCTokens {
        let params: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", config.oidcClientID),
            ("scope", config.oidcScopes)
        ]
        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await postForm(tokenURL, params: params)
        } catch {
            throw AuthError.transientRefreshFailure(error)
        }

        if http.statusCode == 200 {
            return try JSONDecoder().decode(OIDCTokens.self, from: data)
        }
        let body = String(data: data, encoding: .utf8) ?? "unknown"
        if (400...499).contains(http.statusCode) {
            logger.error("Refresh rejected (\(http.statusCode)): \(body, privacy: .public)")
            throw AuthError.refreshTokenInvalid(body)
        }
        logger.warning("Refresh failed transiently (\(http.statusCode))")
        throw AuthError.transientRefreshFailure(URLError(.badServerResponse))
    }

    private func postForm(_ url: URL, params: [(String, String)]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params).data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private func storeTokens(_ tokens: OIDCTokens) {
        setKeychainItem(account: "oidc_access_token", value: tokens.accessToken)
        if let refresh = tokens.refreshToken {
            setKeychainItem(account: "oidc_refresh_token", value: refresh)
        }
        if let expiresIn = tokens.expiresIn {
            let expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
            setKeychainItem(
                account: "oidc_token_expiry",
                value: String(expiry.timeIntervalSince1970)
            )
        } else {
            deleteKeychainItem(account: "oidc_token_expiry")
            logger.warning("storeTokens: missing expiresIn — cannot track expiry")
        }
    }

    // MARK: - Keychain

    private static let keychainService = "org.davidjensenius.TelephoneBoothOperatorMobile.oidc"

    private func setKeychainItem(account: String, value: String) {
        deleteKeychainItem(account: account)
        guard let data = value.data(using: .utf8) else { return }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != noErr {
            logger.error("Keychain write failed for \(account, privacy: .public): \(status)")
        }
    }

    private func getKeychainItem(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == noErr, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Helpers

    private static func formEncode(_ params: [(String, String)]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return params.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedVal = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedVal)"
        }.joined(separator: "&")
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func generateRandomString() -> String {
        var buf = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
        return base64URLEncode(Data(buf))
    }
}
