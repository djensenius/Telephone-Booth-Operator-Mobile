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
        NotificationManager.registerNotificationCategories()
        #if os(iOS) || os(visionOS)
        WidgetRefreshScheduler.register()
        #endif
        #if os(iOS)
        Task { @MainActor in WatchAuthSync.shared.activate() }
        #endif
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

    #if os(iOS) || os(visionOS)
    public func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let result = await WidgetRefreshScheduler.refreshNow()
            WidgetRefreshScheduler.schedule()

            switch result {
            case .newData:
                completionHandler(.newData)
            case .noData:
                completionHandler(.noData)
            case .failed:
                completionHandler(.failed)
            }
        }
    }
    #endif

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
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let content = response.notification.request.content
        let target = NotificationManager.navigationTarget(
            categoryIdentifier: content.categoryIdentifier,
            userInfo: content.userInfo
        )
        Task { @MainActor in
            if let target {
                NotificationManager.shared.route(to: target)
            }
            // UIKit performs foreground state restoration when this returns.
            // Complete on the main actor instead of the async protocol bridge's
            // cooperative-pool executor.
            completionHandler()
            await PendingMessagesStore.shared.refresh(using: .shared)
        }
    }
    #endif
}
#endif

#if canImport(AppKit)
import AppKit

public final class TBOperatorMacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.registerNotificationCategories()
        WidgetRefreshScheduler.register()
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

    public func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        Task { @MainActor in
            _ = await WidgetRefreshScheduler.refreshNow()
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
        let content = response.notification.request.content
        if let target = NotificationManager.navigationTarget(
            categoryIdentifier: content.categoryIdentifier,
            userInfo: content.userInfo
        ) {
            await NotificationManager.shared.route(to: target)
        }
        await PendingMessagesStore.shared.refresh(using: .shared)
    }
}
#endif

#if canImport(WatchKit)
import WatchKit

public final class TBOperatorWatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    public func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.registerNotificationCategories()
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
