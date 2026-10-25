//
//  AuthManager+MacWidgets.swift
//  TelephoneBoothOperatorMobile
//

#if os(macOS)
import Foundation

extension AuthManager {
    func coordinateWidgetRefresh(generation: Int) async -> (lock: MacWidgetFileLock?, outcome: RefreshOutcome?) {
        guard keychainStore is SystemKeychainStore else { return (nil, nil) }
        let previousAccessToken = getAccessToken()
        do {
            let lock = try await MacWidgetFileLock.refreshLock()
            guard generation == sessionGeneration else { return (lock, .rejected) }
            // The extension may have rotated the token while we waited for its lock.
            if getAccessToken() != previousAccessToken, !isTokenExpiringSoon() { return (lock, .refreshed) }
            return (lock, nil)
        } catch {
            return (nil, .transientFailure)
        }
    }
}
#endif
