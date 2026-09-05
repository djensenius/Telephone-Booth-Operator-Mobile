//
//  AuthManager+WatchBroker.swift
//  TelephoneBoothOperatorMobile
//
//  Phone-as-broker token helpers for the watch handoff. The paired iPhone
//  vends short-lived access tokens to the standalone watch app; the refresh
//  token never leaves the phone (Authentik rotates refresh tokens, so two
//  devices sharing one lineage would invalidate each other). See
//  `WatchAuthSync` for the WatchConnectivity transport.
//

import Foundation
import os

private let logger = authManagerLogger

extension AuthManager {

    #if os(iOS)
    /// Returns a fresh access token for the paired watch, refreshing the
    /// phone's own session first if needed. Returns nil when signed out or
    /// in demo mode.
    func brokerAccessTokenForWatch(forceRefresh: Bool = false) async -> (accessToken: String, expiry: Double)? {
        guard !AppConfig.shared.isDemoMode else { return nil }
        let generation = sessionGeneration
        if forceRefresh, await refreshSession() != .refreshed { return nil }
        guard await ensureValidToken(), let token = getAccessToken() else { return nil }
        guard generation == sessionGeneration, !AppConfig.shared.isDemoMode,
              let expiry = getKeychainItem(account: "oidc_token_expiry").flatMap(Double.init),
              expiry.isFinite, expiry > Date().timeIntervalSince1970 else { return nil }
        return (token, expiry)
    }
    #endif

    /// Stores an access token brokered from the paired phone. The watch
    /// operates in "brokered mode" with no refresh token of its own, so any
    /// stale refresh token is removed to keep the watch from attempting an
    /// independent (and rotation-conflicting) refresh.
    func applyBrokeredAccessToken(accessToken: String, expiry: Double) -> Bool {
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expiry.isFinite, expiry > Date().timeIntervalSince1970 else { return false }
        // Invalidate the previous expiry first: a failed write must never make
        // a replacement token look valid for the previous token's lifetime.
        deleteKeychainItem(account: "oidc_token_expiry")
        guard setKeychainItem(account: "oidc_access_token", value: accessToken),
              setKeychainItem(account: "oidc_token_expiry", value: String(expiry)) else {
            deleteKeychainItem(account: "oidc_access_token")
            deleteKeychainItem(account: "oidc_token_expiry")
            logger.error("Could not persist paired-phone credentials")
            return false
        }
        deleteKeychainItem(account: "oidc_refresh_token")
        sessionRestored()
        logger.info("Applied brokered access token from paired phone")
        return true
    }
}
