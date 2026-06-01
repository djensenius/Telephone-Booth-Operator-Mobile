//
//  NotificationDelegateAdaptors.swift
//  TelephoneBoothOperatorMobile
//
//  Tiny platform-specific delegate shims that forward APNs token
//  registration callbacks into `NotificationManager`. Each app target
//  attaches the right adaptor via `@UIApplicationDelegateAdaptor` /
//  `@NSApplicationDelegateAdaptor` / `@WKApplicationDelegateAdaptor`
//  in its `App.swift`.
//

import Foundation
import UserNotifications
import os

#if canImport(UIKit) && !os(watchOS)
import UIKit

public final class TBOperatorAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in WatchAuthSync.shared.activate() }
        return true
    }

    public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await NotificationManager.shared.tokenRegistered(rawData: deviceToken)
        }
    }

    public func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.tokenRegistrationFailed(error: error)
        }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Task { await PendingMessagesStore.shared.refresh(using: .shared) }
        return [.banner, .list, .sound, .badge]
    }

    #if !os(tvOS)
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await PendingMessagesStore.shared.refresh(using: .shared)
    }
    #endif
}
#endif

#if canImport(AppKit)
import AppKit

public final class TBOperatorMacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    public func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await NotificationManager.shared.tokenRegistered(rawData: deviceToken)
        }
    }

    public func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.tokenRegistrationFailed(error: error)
        }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Task { await PendingMessagesStore.shared.refresh(using: .shared) }
        return [.banner, .list, .sound, .badge]
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await PendingMessagesStore.shared.refresh(using: .shared)
    }
}
#endif

#if canImport(WatchKit)
import WatchKit

public final class TBOperatorWatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    public func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in WatchAuthSync.shared.activate() }
    }

    public func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        Task { @MainActor in
            await NotificationManager.shared.tokenRegistered(rawData: deviceToken)
        }
    }

    public func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {
        Task { @MainActor in
            NotificationManager.shared.tokenRegistrationFailed(error: error)
        }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
#endif
