//
//  AuthManager+DeviceFlow.swift
//  TelephoneBoothOperatorMobile
//
//  OAuth 2.0 Device Authorization Grant (RFC 8628) flow used by tvOS
//  to sign in without an embedded browser. The companion phone/Mac
//  app visits the verification URL and enters the displayed
//  user_code; this extension polls the token endpoint until that
//  happens.
//

import Foundation

extension AuthManager {
    /// Begins an OAuth 2.0 Device Authorization Grant flow. Returns the
    /// `user_code`, verification URL, polling interval, and the
    /// `device_code` that callers pass to `pollForDeviceToken`.
    public func beginDeviceAuthorization() async throws -> DeviceAuthorization {
        let params: [(String, String)] = [
            ("client_id", AppConfig.shared.oidcClientID),
            ("scope", AppConfig.shared.oidcScopes)
        ]
        let (data, http): (Data, HTTPURLResponse)
        do {
            (data, http) = try await postForm(deviceAuthorizationURL, params: params)
        } catch {
            throw AuthError.deviceAuthorizationFailed(error.localizedDescription)
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            authManagerLogger.error("Device authorization failed (\(http.statusCode)): \(body, privacy: .public)")
            throw AuthError.deviceAuthorizationFailed(body)
        }
        do {
            return try JSONDecoder().decode(DeviceAuthorization.self, from: data)
        } catch {
            throw AuthError.deviceAuthorizationFailed(error.localizedDescription)
        }
    }

    /// Polls the token endpoint at the requested cadence until the user
    /// completes authorization, the code expires, or the task is
    /// cancelled. Sets `authState = .signedIn` on success.
    public func pollForDeviceToken(
        deviceCode: String,
        interval: Int,
        expiresIn: Int
    ) async throws {
        var currentInterval = max(1, interval)
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(currentInterval) * 1_000_000_000)
            if Task.isCancelled { throw AuthError.cancelled }
            let outcome = await exchangeDeviceCode(deviceCode)
            switch outcome {
            case .tokens(let tokens):
                storeTokens(tokens)
                markSignedIn()
                authManagerLogger.info("Signed in via device flow")
                return
            case .pending:
                continue
            case .slowDown:
                currentInterval += 5
            case .denied:
                throw AuthError.deviceAuthorizationDenied
            case .expired:
                throw AuthError.deviceCodeExpired
            case .otherError(let body):
                throw AuthError.tokenExchangeFailed(body)
            }
        }
        throw AuthError.deviceCodeExpired
    }

    private enum DevicePollOutcome {
        case tokens(OIDCTokens)
        case pending
        case slowDown
        case denied
        case expired
        case otherError(String)
    }

    private func exchangeDeviceCode(_ deviceCode: String) async -> DevicePollOutcome {
        let params: [(String, String)] = [
            ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
            ("device_code", deviceCode),
            ("client_id", AppConfig.shared.oidcClientID)
        ]
        do {
            let (data, http) = try await postForm(tokenURL, params: params)
            if http.statusCode == 200 {
                let tokens = try JSONDecoder().decode(OIDCTokens.self, from: data)
                return .tokens(tokens)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            let error = Self.parseOAuthError(body)
            switch error {
            case "authorization_pending": return .pending
            case "slow_down": return .slowDown
            case "access_denied": return .denied
            case "expired_token": return .expired
            default: return .otherError(body)
            }
        } catch {
            return .otherError(error.localizedDescription)
        }
    }

    static func parseOAuthError(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json["error"] as? String else {
            return ""
        }
        return value
    }
}
