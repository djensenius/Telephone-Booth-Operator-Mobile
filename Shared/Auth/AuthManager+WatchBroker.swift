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
    func brokerAccessTokenForWatch() async -> (accessToken: String, expiry: Double)? {
        guard !AppConfig.shared.isDemoMode else { return nil }
        guard await ensureValidToken(), let token = getAccessToken() else { return nil }
        let expiry = getKeychainItem(account: "oidc_token_expiry").flatMap(Double.init)
            ?? Date().addingTimeInterval(300).timeIntervalSince1970
        return (token, expiry)
    }
    #endif

    #if os(watchOS)
    /// Stores an access token brokered from the paired phone. The watch
    /// operates in "brokered mode" with no refresh token of its own, so any
    /// stale refresh token is removed to keep the watch from attempting an
    /// independent (and rotation-conflicting) refresh.
    func applyBrokeredAccessToken(accessToken: String, expiry: Double) -> Bool {
        let stored = setKeychainItem(account: "oidc_access_token", value: accessToken)
        setKeychainItem(account: "oidc_token_expiry", value: String(expiry))
        deleteKeychainItem(account: "oidc_refresh_token")
        if stored {
            markSignedIn()
            logger.info("Applied brokered access token from paired phone")
        }
        return stored
    }
    #endif
}
