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

struct DeliveredNotificationDescriptor: Sendable {
    let categoryIdentifier: String
    let messageId: String?
    let sessionId: String?
    let hasModerationQueuePayload: Bool
}

public enum DeliveredNotificationScope: Equatable, Sendable {
    case allMessages
    case messages(ids: Set<String>)
    case allCalls
    case session(id: String)
}

extension NotificationManager {
    public func clearDeliveredNotifications(in scope: DeliveredNotificationScope) async {
        #if os(tvOS)
        return
        #else
        let center = UNUserNotificationCenter.current()
        let notifications = await center.deliveredNotifications()
        let identifiers = notifications.compactMap { notification in
            let content = notification.request.content
            return Self.shouldClearDeliveredNotification(
                categoryIdentifier: content.categoryIdentifier,
                userInfo: content.userInfo,
                in: scope
            ) ? notification.request.identifier : nil
        }
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        #endif
    }

    func markNotificationScopeVisible(_ scope: DeliveredNotificationScope, id: UUID) {
        visibleNotificationScopes[id] = scope
    }

    func markNotificationScopeHidden(id: UUID) {
        visibleNotificationScopes[id] = nil
    }

    func isViewingNotification(_ descriptor: DeliveredNotificationDescriptor) -> Bool {
        visibleNotificationScopes.values.contains { scope in
            Self.shouldClearDeliveredNotification(descriptor, in: scope)
        }
    }

    public nonisolated static func shouldClearDeliveredNotification(
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any],
        in scope: DeliveredNotificationScope
    ) -> Bool {
        shouldClearDeliveredNotification(
            deliveredNotificationDescriptor(
                categoryIdentifier: categoryIdentifier,
                userInfo: userInfo
            ),
            in: scope
        )
    }

    nonisolated static func deliveredNotificationDescriptor(
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> DeliveredNotificationDescriptor {
        DeliveredNotificationDescriptor(
            categoryIdentifier: categoryIdentifier,
            messageId: stringValue(for: ["messageId", "message_id"], in: userInfo),
            sessionId: stringValue(for: ["sessionId", "session_id"], in: userInfo),
            hasModerationQueuePayload: hasModerationQueuePayload(userInfo)
        )
    }

    nonisolated static func shouldClearDeliveredNotification(
        _ descriptor: DeliveredNotificationDescriptor,
        in scope: DeliveredNotificationScope
    ) -> Bool {
        switch scope {
        case .allMessages:
            return descriptor.categoryIdentifier == Category.message
                || descriptor.messageId != nil
                || descriptor.hasModerationQueuePayload
        case .messages(let ids):
            guard let messageId = descriptor.messageId else {
                return false
            }
            return ids.contains(messageId)
        case .allCalls:
            return descriptor.categoryIdentifier == Category.call || descriptor.sessionId != nil
        case .session(let id):
            return descriptor.sessionId == id
        }
    }
}

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
        let notificationCount = MessageNotificationAggregation.count(userInfo: userInfo)
        Task { @MainActor in
            if let notificationCount {
                await PendingMessagesStore.shared.applyNotificationCount(notificationCount)
            }
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
        #if os(tvOS)
        return []
        #else
        let content = notification.request.content
        let notificationCount = MessageNotificationAggregation.count(userInfo: content.userInfo)
        Task {
            if let notificationCount {
                await PendingMessagesStore.shared.applyNotificationCount(notificationCount)
            }
            await PendingMessagesStore.shared.refresh(using: .shared)
        }
        let descriptor = NotificationManager.deliveredNotificationDescriptor(
            categoryIdentifier: content.categoryIdentifier,
            userInfo: content.userInfo
        )
        if await NotificationManager.shared.isViewingNotification(descriptor) {
            return []
        }
        return [.banner, .list, .sound, .badge]
        #endif
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
        let notificationCount = MessageNotificationAggregation.count(userInfo: content.userInfo)
        Task { @MainActor in
            if let notificationCount {
                await PendingMessagesStore.shared.applyNotificationCount(notificationCount)
            }
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
        let notificationCount = MessageNotificationAggregation.count(userInfo: userInfo)
        Task { @MainActor in
            if let notificationCount {
                await PendingMessagesStore.shared.applyNotificationCount(notificationCount)
            }
            _ = await WidgetRefreshScheduler.refreshNow()
        }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        let notificationCount = MessageNotificationAggregation.count(userInfo: content.userInfo)
        Task {
            if let notificationCount {
                await PendingMessagesStore.shared.applyNotificationCount(notificationCount)
            }
            await PendingMessagesStore.shared.refresh(using: .shared)
        }
        let descriptor = NotificationManager.deliveredNotificationDescriptor(
            categoryIdentifier: content.categoryIdentifier,
            userInfo: content.userInfo
        )
        if await NotificationManager.shared.isViewingNotification(descriptor) {
            return []
        }
        return [.banner, .list, .sound, .badge]
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        if let notificationCount = MessageNotificationAggregation.count(userInfo: content.userInfo) {
            await PendingMessagesStore.shared.applyNotificationCount(notificationCount)
        }
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
        let content = notification.request.content
        if let notificationCount = MessageNotificationAggregation.count(userInfo: content.userInfo) {
            await PendingMessagesStore.shared.applyNotificationCount(notificationCount)
        }
        let descriptor = NotificationManager.deliveredNotificationDescriptor(
            categoryIdentifier: content.categoryIdentifier,
            userInfo: content.userInfo
        )
        if await NotificationManager.shared.isViewingNotification(descriptor) {
            return []
        }
        return [.banner, .list, .sound]
    }
}
#endif
