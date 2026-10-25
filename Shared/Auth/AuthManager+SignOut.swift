//
//  AuthManager+SignOut.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

extension AuthManager {
    public func signOut() {
        sessionGeneration &+= 1
        #if os(macOS)
        MacWidgetSession.revokeCredentials()
        #endif
        #if os(watchOS)
        UserDefaults.standard.set(true, forKey: WatchAuthSync.autoSignInPausedKey)
        #endif
        restoreRetryTask?.cancel()
        restoreRetryTask = nil
        sessionRestoreFailed = false
        NotificationManager.shared.resetForSignOut()
        suspendWidgetRefreshUntilSignIn()
        deleteKeychainItem(account: "oidc_access_token")
        deleteKeychainItem(account: "oidc_refresh_token")
        deleteKeychainItem(account: "oidc_token_expiry")
        authState = .signedOut
        authManagerLogger.info("Signed out")
    }

    func suspendWidgetRefreshUntilSignIn() {
        #if os(macOS)
        MacWidgetSession.disable()
        #endif
        WidgetSnapshotStore.disableWritesAndClear()
        widgetCleanupGeneration &+= 1
        let generation = widgetCleanupGeneration
        let previousCleanup = widgetCleanupTask
        widgetCleanupTask = Task { @MainActor [weak self] in
            _ = await previousCleanup?.value
            await WidgetRefreshScheduler.stopAndClear()
            if self?.widgetCleanupGeneration == generation {
                self?.widgetCleanupTask = nil
            }
        }
    }

    public func signOutRevokingNotifications() async {
        await NotificationManager.shared.revokeForSignOut()
        signOut()
    }

    func prepareWidgetRefresh() async -> Bool {
        let cleanup = widgetCleanupTask
        _ = await cleanup?.value
        #if os(macOS)
        guard !AppConfig.shared.isDemoMode else { return false }
        #endif
        guard await ensureValidToken() else { return false }
        if authState == .unknown {
            sessionRestored()
        }
        guard authState == .signedIn else { return false }
        #if os(macOS)
        guard !AppConfig.shared.isDemoMode else { return false }
        if keychainStore is SystemKeychainStore {
            MacWidgetSession.publish(
                apiBaseURL: AppConfig.shared.apiBaseURL,
                tokenURL: tokenURL,
                clientID: AppConfig.shared.oidcClientID,
                scopes: AppConfig.shared.oidcScopes
            )
        }
        #endif
        WidgetSnapshotStore.enableWrites()
        await WidgetRefreshCoordinator.shared.activate()
        return true
    }
}
