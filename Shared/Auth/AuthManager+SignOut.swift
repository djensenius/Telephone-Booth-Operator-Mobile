//
//  AuthManager+SignOut.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

extension AuthManager {
    public func signOut() {
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
        guard await ensureValidToken() else { return false }
        if authState == .unknown {
            sessionRestored()
        }
        guard authState == .signedIn else { return false }
        WidgetSnapshotStore.enableWrites()
        await WidgetRefreshCoordinator.shared.activate()
        return true
    }
}
