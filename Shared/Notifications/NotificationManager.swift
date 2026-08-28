//
//  NotificationManager.swift
//  TelephoneBoothOperatorMobile
//
//  Drives the APNs-token + permission lifecycle. The platform-specific
//  delegate adaptors call `tokenRegistered(_:)` on this manager when the
//  OS hands us a device token; the manager then registers / refreshes
//  the device with the operator and persists the returned id so we can
//  PATCH preferences later.
//

import Foundation
import Observation
import UserNotifications
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(WatchKit)
import WatchKit
#endif

private let logger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "NotificationManager"
)

/// Public state surfaced to SwiftUI views (Settings, primarily).
public enum NotificationAuthorizationState: Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case authorized
    case provisional
}

@MainActor
@Observable
public final class NotificationManager {
    public static let shared = NotificationManager()

    public private(set) var authorizationState: NotificationAuthorizationState = .unknown
    public private(set) var deviceId: String?
    public private(set) var apnsToken: String?
    public private(set) var preferences: MobileDevicePreferences
    public private(set) var lastError: String?
    public private(set) var isWorking: Bool = false
    public var navigationTarget: NotificationNavigationTarget? {
        guard let target = navigationStore.pendingTarget else { return nil }
        return NotificationNavigationTarget(appNavigationTarget: target)
    }

    private let defaults: UserDefaults
    private let client: OperatorClient
    private let navigationStore: AppNavigationStore

    /// Latest preferences waiting to be sent to the server.
    private var pendingPreferences: MobileDevicePreferences?
    /// The active debounce-then-send pipeline; ensures only one flight at a time.
    private var syncTask: Task<Void, Never>?
    private var registrationTask: Task<Void, Never>?
    private var registrationGeneration: UInt = 0
    private var registrationEnabled = false
    var visibleNotificationScopes: [UUID: DeliveredNotificationScope] = [:]
    /// Debounce interval for coalescing rapid preference changes.
    private let debounceInterval: Duration

    private enum Keys {
        static let deviceId = "notifications.deviceId"
        static let apnsToken = "notifications.apnsToken"
        static let preferences = "notifications.preferences"
    }

    enum Category {
        static let call = "BOOTH_CALL"
        static let message = "BOOTH_MESSAGE"
    }

    private enum Action {
        static let view = "VIEW_DETAILS"
    }

    public init(
        defaults: UserDefaults = .standard,
        client: OperatorClient = .shared,
        navigationStore: AppNavigationStore = .shared,
        debounceInterval: Duration = .milliseconds(300)
    ) {
        self.defaults = defaults
        self.client = client
        self.navigationStore = navigationStore
        self.debounceInterval = debounceInterval
        self.deviceId = defaults.string(forKey: Keys.deviceId)
        self.apnsToken = defaults.string(forKey: Keys.apnsToken)
        if let data = defaults.data(forKey: Keys.preferences),
           let decoded = try? JSONDecoder().decode(MobileDevicePreferences.self, from: data) {
            self.preferences = decoded
        } else {
            self.preferences = .defaults
        }
    }

    public func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationState = mapStatus(settings.authorizationStatus)
    }

    public func requestAuthorizationAndRegister() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            if granted {
                registrationEnabled = true
                Self.registerNotificationCategories()
                registerForRemoteNotifications()
            }
        } catch {
            lastError = error.localizedDescription
            logger.error("authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Refreshes APNs registration after launch or sign-in. Apple can rotate
    /// device tokens, so registration must not depend solely on the Settings
    /// button having been tapped during an earlier install.
    public func synchronizeRegistrationIfAuthorized() async {
        #if os(tvOS)
        return
        #else
        await refreshAuthorizationStatus()
        guard authorizationState == .authorized || authorizationState == .provisional else {
            return
        }
        registrationEnabled = true
        Self.registerNotificationCategories()
        registerForRemoteNotifications()
        #endif
    }

    /// Revokes the server-side device while the bearer token is still
    /// available, then removes the local APNs registration.
    public func revokeForSignOut() async {
        await stopRegistrationWork()

        if let id = deviceId {
            isWorking = true
            defer { isWorking = false }
            do {
                try await client.revokeDevice(id: id)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                logger.error("sign-out revokeDevice failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        clearLocalRegistration()
        unregisterForRemoteNotifications()
    }

    public func disableNotifications() async {
        await stopRegistrationWork()
        guard let id = deviceId else {
            clearLocalRegistration()
            unregisterForRemoteNotifications()
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.revokeDevice(id: id)
        } catch {
            // Ignore revoke failures; the user has indicated intent to
            // disable, so we still clear the local registration state.
            logger.warning("revokeDevice failed: \(error.localizedDescription, privacy: .public)")
        }
        clearLocalRegistration()
        unregisterForRemoteNotifications()
    }

    public func tokenRegistered(rawData: Data) async {
        guard registrationEnabled else { return }
        let hex = rawData.map { String(format: "%02x", $0) }.joined()
        apnsToken = hex
        defaults.set(hex, forKey: Keys.apnsToken)
        await startRegistration(token: hex)
    }

    public func tokenRegistrationFailed(error: Error) {
        lastError = error.localizedDescription
        logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    public func route(to target: NotificationNavigationTarget) {
        navigationStore.route(to: target.appNavigationTarget)
    }

    public func clearNavigationTarget() {
        navigationStore.clearPendingTarget()
    }

    public func resetForSignOut() {
        registrationEnabled = false
        registrationGeneration &+= 1
        registrationTask?.cancel()
        registrationTask = nil
        syncTask?.cancel()
        syncTask = nil
        pendingPreferences = nil
        visibleNotificationScopes.removeAll()
        navigationStore.clearPendingTarget()
        clearLocalRegistration()
        unregisterForRemoteNotifications()
    }

    public nonisolated static func navigationTarget(
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> NotificationNavigationTarget? {
        if let messageId = stringValue(for: ["messageId", "message_id"], in: userInfo) {
            return .messages(messageId: messageId)
        }
        if let sessionId = stringValue(for: ["sessionId", "session_id"], in: userInfo) {
            return .session(id: sessionId)
        }

        switch categoryIdentifier {
        case Category.message:
            return hasModerationQueuePayload(userInfo) ? .reviewQueue : .messages(messageId: nil)
        default:
            return nil
        }
    }

    public nonisolated static func registerNotificationCategories() {
        #if !os(tvOS)
        let viewAction = UNNotificationAction(
            identifier: Action.view,
            title: "View Details",
            options: [.foreground]
        )
        let categories = [
            UNNotificationCategory(
                identifier: Category.call,
                actions: [viewAction],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Category.message,
                actions: [viewAction],
                intentIdentifiers: []
            )
        ]
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
        #endif
    }

    /// Retries server registration using the persisted APNs token.
    /// Use when the token exists but a previous `registerDevice` call failed.
    public func retryServerRegistration() async {
        guard let token = apnsToken else { return }
        registrationEnabled = true
        await startRegistration(token: token)
    }

    public func updatePreference(
        _ keyPath: WritableKeyPath<MobileDevicePreferences, Bool>,
        to value: Bool
    ) async {
        var next = preferences
        next[keyPath: keyPath] = value
        await applyPreferences(next)
    }

    public func applyPreferences(_ next: MobileDevicePreferences) async {
        // Optimistic local update so UI reflects intent immediately.
        preferences = next
        persistPreferences(next)

        guard deviceId != nil else { return }

        // Coalesce: store latest desired state and kick off the sync pipeline.
        pendingPreferences = next
        scheduleSyncIfNeeded()
    }

    /// Launches a debounce-then-send loop if one isn't already running.
    private func scheduleSyncIfNeeded() {
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.syncLoop()
        }
    }

    /// Waits for the debounce interval, then sends the latest coalesced
    /// preferences. Loops until no more pending changes arrive during flight.
    private func syncLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: debounceInterval)
            } catch {
                break
            }

            // Snapshot and clear pending so new changes during the request
            // will re-trigger a send.
            guard let snapshot = pendingPreferences else { break }
            pendingPreferences = nil

            await sendPreferencesToServer(snapshot)

            // If more changes arrived while we were sending, loop again.
            if pendingPreferences == nil {
                break
            }
        }
        syncTask = nil
    }

    private func sendPreferencesToServer(_ prefs: MobileDevicePreferences) async {
        guard let id = deviceId else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.updateDevice(
                id: id,
                body: UpdateMobileDevicePreferencesRequest(preferences: prefs)
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            logger.error("updateDevice failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startRegistration(token: String) async {
        registrationGeneration &+= 1
        let generation = registrationGeneration
        registrationTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.syncRegistrationWithServer(token: token, generation: generation)
        }
        registrationTask = task
        await task.value
        if generation == registrationGeneration {
            registrationTask = nil
        }
    }

    private func stopRegistrationWork() async {
        registrationEnabled = false
        registrationGeneration &+= 1
        registrationTask?.cancel()
        if let registrationTask {
            await registrationTask.value
        }
        registrationTask = nil
        syncTask?.cancel()
        syncTask = nil
        pendingPreferences = nil
    }

    private func syncRegistrationWithServer(token: String, generation: UInt) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let device = try await client.registerDevice(
                RegisterMobileDeviceRequest(
                    apnsToken: token,
                    platform: Self.currentPlatform(),
                    deviceName: Self.deviceName(),
                    preferences: preferences
                )
            )
            guard registrationEnabled, generation == registrationGeneration else {
                do {
                    try await client.revokeDevice(id: device.id)
                } catch {
                    logger.warning(
                        "stale registration revoke failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                return
            }
            deviceId = device.id
            defaults.set(device.id, forKey: Keys.deviceId)
            preferences = device.preferences
            persistPreferences(device.preferences)
            lastError = nil
        } catch {
            guard registrationEnabled, generation == registrationGeneration else { return }
            lastError = error.localizedDescription
            logger.error("registerDevice failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistPreferences(_ value: MobileDevicePreferences) {
        if let encoded = try? JSONEncoder().encode(value) {
            defaults.set(encoded, forKey: Keys.preferences)
        }
    }

    private func clearLocalRegistration() {
        deviceId = nil
        apnsToken = nil
        defaults.removeObject(forKey: Keys.deviceId)
        defaults.removeObject(forKey: Keys.apnsToken)
    }

    private func mapStatus(_ status: UNAuthorizationStatus) -> NotificationAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .ephemeral: return .authorized
        case .provisional: return .provisional
        @unknown default: return .unknown
        }
    }

    private func registerForRemoteNotifications() {
        #if canImport(WatchKit)
        WKApplication.shared().registerForRemoteNotifications()
        #elseif canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif canImport(AppKit)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    private func unregisterForRemoteNotifications() {
        #if canImport(WatchKit)
        WKApplication.shared().unregisterForRemoteNotifications()
        #elseif canImport(UIKit)
        UIApplication.shared.unregisterForRemoteNotifications()
        #elseif canImport(AppKit)
        NSApplication.shared.unregisterForRemoteNotifications()
        #endif
    }

    nonisolated static func stringValue(
        for keys: [String],
        in userInfo: [AnyHashable: Any]
    ) -> String? {
        for key in keys {
            if let value = userInfo[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    nonisolated static func hasModerationQueuePayload(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo["awaitingModeration"] != nil || userInfo["awaiting_moderation"] != nil
    }

    private static func currentPlatform() -> MobileDevicePlatform {
        #if os(iOS)
        return .iOS(isPad: UIDevice.current.userInterfaceIdiom == .pad)
        #else
        return .current
        #endif
    }

    private static func deviceName() -> String? {
        #if canImport(WatchKit)
        return WKInterfaceDevice.current().name
        #elseif canImport(UIKit)
        return UIDevice.current.name
        #elseif canImport(AppKit)
        return Host.current().localizedName
        #else
        return nil
        #endif
    }
}
