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

    private let defaults: UserDefaults
    private let client: OperatorClient

    /// Latest preferences waiting to be sent to the server.
    private var pendingPreferences: MobileDevicePreferences?
    /// The active debounce-then-send pipeline; ensures only one flight at a time.
    private var syncTask: Task<Void, Never>?
    /// Debounce interval for coalescing rapid preference changes.
    private let debounceInterval: Duration

    private enum Keys {
        static let deviceId = "notifications.deviceId"
        static let apnsToken = "notifications.apnsToken"
        static let preferences = "notifications.preferences"
    }

    public init(
        defaults: UserDefaults = .standard,
        client: OperatorClient = .shared,
        debounceInterval: Duration = .milliseconds(300)
    ) {
        self.defaults = defaults
        self.client = client
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
                registerForRemoteNotifications()
            }
        } catch {
            lastError = error.localizedDescription
            logger.error("authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func disableNotifications() async {
        guard let id = deviceId else {
            clearLocalRegistration()
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
        let hex = rawData.map { String(format: "%02x", $0) }.joined()
        apnsToken = hex
        defaults.set(hex, forKey: Keys.apnsToken)
        await syncRegistrationWithServer(token: hex)
    }

    public func tokenRegistrationFailed(error: Error) {
        lastError = error.localizedDescription
        logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Retries server registration using the persisted APNs token.
    /// Use when the token exists but a previous `registerDevice` call failed.
    public func retryServerRegistration() async {
        guard let token = apnsToken else { return }
        await syncRegistrationWithServer(token: token)
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

    private func syncRegistrationWithServer(token: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let device = try await client.registerDevice(
                RegisterMobileDeviceRequest(
                    apnsToken: token,
                    platform: .current,
                    deviceName: Self.deviceName(),
                    preferences: preferences
                )
            )
            deviceId = device.id
            defaults.set(device.id, forKey: Keys.deviceId)
            preferences = device.preferences
            persistPreferences(device.preferences)
            lastError = nil
        } catch {
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
