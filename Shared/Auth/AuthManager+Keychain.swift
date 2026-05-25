//
//  AuthManager+Keychain.swift
//  TelephoneBoothOperatorMobile
//
//  Keychain storage helpers for OIDC tokens.
//

import Foundation
import os

private let logger = authManagerLogger

extension AuthManager {

    static let keychainService = "org.davidjensenius.TelephoneBoothOperatorMobile.oidc"

    /// Migrates existing Keychain items from `kSecAttrAccessibleAfterFirstUnlock`
    /// to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. This prevents tokens
    /// from being restored to other devices via iCloud Backup.
    func migrateKeychainAccessibility() {
        let accounts = ["oidc_access_token", "oidc_refresh_token", "oidc_token_expiry"]
        for account in accounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.keychainService,
                kSecAttrAccount as String: account
            ]
            let update: [String: Any] = [
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if status == noErr {
                logger.info("Migrated keychain accessibility for \(account, privacy: .public)")
            } else if status != errSecItemNotFound {
                logger.warning(
                    "Keychain accessibility migration failed for \(account, privacy: .public): \(status)"
                )
            }
        }
    }

    @discardableResult
    func setKeychainItem(account: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary, updateAttrs as CFDictionary
        )
        if updateStatus == noErr {
            return true
        }
        if updateStatus == errSecItemNotFound {
            var addAttrs = query
            addAttrs[kSecValueData as String] = data
            addAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addAttrs as CFDictionary, nil)
            if addStatus == noErr {
                return true
            }
            logger.error(
                "Keychain add failed for \(account, privacy: .public): \(addStatus)"
            )
            return false
        }
        logger.error(
            "Keychain update failed for \(account, privacy: .public): \(updateStatus)"
        )
        return false
    }

    func getKeychainItem(account: String) -> String? {
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

    func deleteKeychainItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
