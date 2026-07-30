//
//  AuthManager+SessionRestore.swift
//  TelephoneBoothOperatorMobile
//
//  Launch/foreground session restore. The rule here is that a cached session
//  is only ever discarded when the provider definitively rejects it (or the
//  operator signs out by hand) — never because the network was unavailable.
//

import Foundation
import os

private let logger = authManagerLogger

extension AuthManager {

    // MARK: - Session lifecycle

    /// Validates the cached session at app launch (and whenever the app
    /// returns to the foreground while the session is still unresolved).
    ///
    /// The session is only cleared when the provider *definitively* rejects
    /// the refresh token. Transient failures (offline, DNS, 5xx, rate
    /// limiting) leave the tokens in the Keychain and schedule a retry, so a
    /// launch without connectivity never costs the user a login.
    public func validateSessionOnLaunch() async {
        await restoreSession(scheduleRetry: true)
    }

    func restoreSession(scheduleRetry: Bool) async {
        guard authState == .unknown else { return }
        #if os(watchOS)
        // Brokered mode: no refresh token of our own. Try the paired phone,
        // then fall back to a still-valid cached access token if it's offline.
        if getKeychainItem(account: "oidc_refresh_token") == nil {
            if await WatchAuthSync.shared.ensureBrokeredToken() {
                sessionRestored()
                logger.info("validateSession: restored via paired-phone broker")
            } else if getAccessToken() != nil, !isTokenExpired() {
                sessionRestored()
                logger.info("validateSession: phone unreachable, cached token still valid")
            } else {
                // The phone may simply be out of range; keep the session and
                // let the watch retry instead of forcing a login.
                sessionRestoreDeferred(scheduleRetry: scheduleRetry)
            }
            return
        }
        #endif
        guard getKeychainItem(account: "oidc_refresh_token") != nil else {
            logger.info("validateSession: no refresh token — signing out")
            signOut()
            return
        }

        switch await refreshSession() {
        case .refreshed:
            sessionRestored()
            logger.info("validateSession: session restored via refresh")
        case .rejected:
            // `refreshSession()` already cleared the Keychain and signed out.
            logger.warning("validateSession: refresh token rejected — signed out")
        case .transientFailure:
            if getAccessToken() != nil, !isTokenExpired() {
                sessionRestored()
                logger.info("validateSession: refresh failed transiently, cached token still valid")
            } else {
                logger.warning("validateSession: provider unreachable — keeping session, will retry")
                sessionRestoreDeferred(scheduleRetry: scheduleRetry)
            }
        }
    }

    /// Retries a session restore that previously failed because the provider
    /// was unreachable.
    public func retrySessionRestore() async {
        restoreRetryTask?.cancel()
        restoreRetryTask = nil
        sessionRestoreFailed = false
        await restoreSession(scheduleRetry: true)
    }

    func sessionRestored() {
        restoreRetryTask?.cancel()
        restoreRetryTask = nil
        sessionRestoreFailed = false
        authState = .signedIn
    }

    /// Keeps the cached (still valid) refresh token, leaves the state
    /// unresolved, and retries in the background with backoff.
    func sessionRestoreDeferred(scheduleRetry: Bool) {
        sessionRestoreFailed = true
        guard scheduleRetry, restoreRetryTask == nil else { return }
        restoreRetryTask = Task { @MainActor [weak self] in
            for delay in [2, 5, 15, 30, 60] {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
                guard let self, self.authState == .unknown else { return }
                await self.restoreSession(scheduleRetry: false)
                if self.authState != .unknown { return }
            }
            self?.restoreRetryTask = nil
        }
    }

    // MARK: - Refresh failure classification

    /// Decides whether a non-200 `/token` response means the session is dead.
    ///
    /// Treating every 4xx as fatal is what makes an app feel like it "logs you
    /// out constantly": a 429 from rate limiting, a 403 from a WAF, or a 404
    /// from a mis-set token URL would all discard a refresh token that is
    /// still good for weeks. Per RFC 6749 §5.2, only these OAuth error codes
    /// mean the grant itself is no longer usable.
    static func isDefinitiveRejection(status: Int, body: Data) -> Bool {
        let fatalCodes: Set<String> = [
            "invalid_grant", "invalid_client", "unauthorized_client", "invalid_scope"
        ]
        if let code = oauthErrorCode(in: body) {
            return fatalCodes.contains(code)
        }
        // No parseable OAuth error payload: a bare 400/401 from a token
        // endpoint still almost always means the grant was refused.
        return status == 400 || status == 401
    }

    static func oauthErrorCode(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let code = object["error"] as? String else {
            return nil
        }
        return code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
