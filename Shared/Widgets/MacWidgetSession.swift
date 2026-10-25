//
//  MacWidgetSession.swift
//  TelephoneBoothOperatorMobile
//

#if os(macOS)
import Darwin
import Foundation
import LocalAuthentication
import Security

/// Cross-process locks: never hold the short state lock across a network await.
final class MacWidgetFileLock: @unchecked Sendable {
    private let descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    static func acquire(name: String, wait: Bool, directoryURL: URL? = nil) throws -> MacWidgetFileLock {
        guard let directory = directoryURL ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroup
        ) else { throw URLError(.cannotOpenFile) }
        let descriptor = open(directory.appendingPathComponent(name).path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw URLError(.cannotOpenFile) }
        guard flock(descriptor, LOCK_EX | (wait ? 0 : LOCK_NB)) == 0 else {
            close(descriptor)
            throw URLError(.resourceUnavailable)
        }
        return MacWidgetFileLock(descriptor: descriptor)
    }

    static func refreshLock() async throws -> MacWidgetFileLock {
        // Bound contention to fit a WidgetKit timeline request; the OS releases
        // flock automatically if either the app or extension is terminated.
        for _ in 0..<100 {
            try Task.checkCancellation()
            if let lock = try? acquire(name: "widget-auth.lock", wait: false) { return lock }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw URLError(.timedOut)
    }

    static func withStateLock<T>(_ body: () throws -> T) throws -> T {
        let lock = try acquire(name: "widget-state.lock", wait: true)
        defer { withExtendedLifetime(lock) {} }
        return try body()
    }
}

/// macOS uses one data-protection Keychain access group for the host and widget.
/// Tokens never enter the App Group files or UserDefaults.
enum MacWidgetKeychain {
    static let service = "org.davidjensenius.TelephoneBoothOperatorMobile.oidc"

    static func query(service: String, account: String) -> [String: Any]? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "WidgetKeychainAccessGroup") as? String,
              !group.isEmpty, !group.contains("$(") else { return nil }
        let authentication = LAContext()
        authentication.interactionNotAllowed = true
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group,
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationContext as String: authentication
        ]
    }

    static func read(service: String = service, account: String) -> String? {
        guard var query = query(service: service, account: account) else { return nil }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(service: String = service, account: String, value: String) -> Bool {
        guard let query = query(service: service, account: account) else { return false }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        let insertion = query.merging(attributes) { _, new in new }
        return SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess
    }

    static func delete(service: String = service, account: String) {
        guard let query = query(service: service, account: account) else { return }
        SecItemDelete(query as CFDictionary)
    }
}

struct MacWidgetSession: Codable, Equatable, Sendable {
    let id: UUID
    let apiBaseURL: URL
    let tokenURL: URL
    let clientID: String
    let scopes: String

    private static let account = "widget-session"

    static func read() -> MacWidgetSession? {
        guard let value = MacWidgetKeychain.read(account: account) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: Data(value.utf8))
    }

    /// Called only by the signed-in host, after session restoration.
    static func publish(apiBaseURL: URL, tokenURL: URL, clientID: String, scopes: String) {
        _ = try? MacWidgetFileLock.withStateLock {
            if let current = read(), current.apiBaseURL == apiBaseURL,
               current.tokenURL == tokenURL, current.clientID == clientID, current.scopes == scopes { return }
            let session = Self(
                id: UUID(), apiBaseURL: apiBaseURL, tokenURL: tokenURL, clientID: clientID, scopes: scopes
            )
            let data = try JSONEncoder().encode(session)
            guard let value = String(data: data, encoding: .utf8) else { return }
            _ = MacWidgetKeychain.write(account: account, value: value)
        }
    }

    static func disable() {
        _ = try? MacWidgetFileLock.withStateLock {
            MacWidgetKeychain.delete(account: account)
        }
    }

    func isCurrent() -> Bool { Self.read() == self }

    func save(_ tokens: OIDCTokens) throws {
        try MacWidgetFileLock.withStateLock {
            guard isCurrent() else { throw URLError(.userAuthenticationRequired) }
            // Persist rotation before the access token so partial writes remain recoverable.
            if let refresh = tokens.refreshToken,
               !MacWidgetKeychain.write(account: "oidc_refresh_token", value: refresh) {
                throw URLError(.cannotWriteToFile)
            }
            guard MacWidgetKeychain.write(account: "oidc_access_token", value: tokens.accessToken) else {
                throw URLError(.cannotWriteToFile)
            }
            if let expiresIn = tokens.expiresIn {
                guard MacWidgetKeychain.write(
                    account: "oidc_token_expiry", value: String(Date().timeIntervalSince1970 + Double(expiresIn))
                ) else { throw URLError(.cannotWriteToFile) }
            } else {
                MacWidgetKeychain.delete(account: "oidc_token_expiry")
            }
        }
    }
}

struct MacWidgetSessionAccess: Sendable {
    var isCurrent: @Sendable () -> Bool
    var readToken: @Sendable (String) -> String?
    var saveTokens: @Sendable (OIDCTokens) throws -> Void
    var acquireRefreshLock: @Sendable () async throws -> MacWidgetFileLock?

    static func live(_ context: MacWidgetSession) -> Self {
        Self(
            isCurrent: { context.isCurrent() },
            readToken: { MacWidgetKeychain.read(account: $0) },
            saveTokens: { try context.save($0) },
            acquireRefreshLock: { try await MacWidgetFileLock.refreshLock() }
        )
    }
}
#endif
