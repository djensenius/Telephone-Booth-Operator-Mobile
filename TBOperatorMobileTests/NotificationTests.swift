//
//  NotificationTests.swift
//

import XCTest
@testable import TBOperatorMobile

final class NotificationTests: XCTestCase {
    func testMessageNotificationAggregationFormatsCurrentQueueCount() {
        let userInfo: [AnyHashable: Any] = [
            "notificationKind": "messageQueue",
            "awaitingModeration": 2
        ]

        XCTAssertTrue(MessageNotificationAggregation.isQueueNotification(userInfo: userInfo))
        XCTAssertEqual(MessageNotificationAggregation.count(userInfo: userInfo), 2)
        XCTAssertEqual(MessageNotificationAggregation.title(count: 2), "2 messages waiting")
        XCTAssertEqual(
            MessageNotificationAggregation.body(count: 2),
            "Booth recordings are ready to moderate."
        )
        XCTAssertEqual(MessageNotificationAggregation.title(count: 1), "1 message waiting")
        XCTAssertEqual(
            MessageNotificationAggregation.count(
                userInfo: ["awaiting_moderation": NSNumber(value: 3)]
            ),
            3
        )
    }

    func testMobileDevicePreferencesRoundTrip() throws {
        let prefs = MobileDevicePreferences(
            callStarted: false,
            messageReceived: true,
            messageFlagged: true,
            moderationQueueHigh: true
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(MobileDevicePreferences.self, from: data)
        XCTAssertEqual(decoded, prefs)
        XCTAssertEqual(decoded.callStarted, false)
        XCTAssertEqual(decoded.moderationQueueHigh, true)
    }

    func testMobileDevicePreferencesDefaults() {
        let defaults = MobileDevicePreferences.defaults
        XCTAssertTrue(defaults.callStarted)
        XCTAssertTrue(defaults.messageReceived)
        XCTAssertTrue(defaults.messageFlagged)
        XCTAssertFalse(defaults.moderationQueueHigh)
    }

    func testMobileDevicePlatformCurrentMatchesCompiledOS() {
        let current = MobileDevicePlatform.current
        #if os(macOS)
        XCTAssertEqual(current, .macos)
        #elseif os(watchOS)
        XCTAssertEqual(current, .watchos)
        #elseif os(tvOS)
        XCTAssertEqual(current, .tvos)
        #elseif os(visionOS)
        XCTAssertEqual(current, .visionos)
        #else
        XCTAssertEqual(current, .ios)
        #endif
    }

    func testIOSPlatformMappingDistinguishesIPad() {
        XCTAssertEqual(MobileDevicePlatform.iOS(isPad: false), .ios)
        XCTAssertEqual(MobileDevicePlatform.iOS(isPad: true), .ipados)
    }

    func testNotificationPayloadRoutesToMessageDetail() {
        let target = NotificationManager.navigationTarget(
            categoryIdentifier: "BOOTH_MESSAGE",
            userInfo: ["messageId": "message-123"]
        )
        XCTAssertEqual(target, .messages(messageId: "message-123"))
    }

    func testNotificationPayloadRoutesToSessionDetail() {
        let target = NotificationManager.navigationTarget(
            categoryIdentifier: "BOOTH_CALL",
            userInfo: ["session_id": "session-123"]
        )
        XCTAssertEqual(target, .session(id: "session-123"))
    }

    func testModerationQueueNotificationRoutesToMessagesList() {
        let target = NotificationManager.navigationTarget(
            categoryIdentifier: "BOOTH_MESSAGE",
            userInfo: ["awaitingModeration": 12, "threshold": 10]
        )
        XCTAssertEqual(target, .reviewQueue)
    }

    func testViewingMessageListClearsMessageNotifications() {
        XCTAssertTrue(
            NotificationManager.shouldClearDeliveredNotification(
                categoryIdentifier: "BOOTH_MESSAGE",
                userInfo: [:],
                in: .allMessages
            )
        )
        XCTAssertTrue(
            NotificationManager.shouldClearDeliveredNotification(
                categoryIdentifier: "",
                userInfo: ["message_id": "message-123"],
                in: .allMessages
            )
        )
        XCTAssertFalse(
            NotificationManager.shouldClearDeliveredNotification(
                categoryIdentifier: "BOOTH_CALL",
                userInfo: ["sessionId": "session-123"],
                in: .allMessages
            )
        )
    }

    func testViewingMessageDetailOnlyClearsMatchingNotification() {
        let scope = DeliveredNotificationScope.messages(ids: ["message-123"])

        XCTAssertTrue(
            NotificationManager.shouldClearDeliveredNotification(
                categoryIdentifier: "BOOTH_MESSAGE",
                userInfo: ["messageId": "message-123"],
                in: scope
            )
        )
        XCTAssertFalse(
            NotificationManager.shouldClearDeliveredNotification(
                categoryIdentifier: "BOOTH_MESSAGE",
                userInfo: ["messageId": "message-456"],
                in: scope
            )
        )
        XCTAssertFalse(
            NotificationManager.shouldClearDeliveredNotification(
                categoryIdentifier: "BOOTH_MESSAGE",
                userInfo: [:],
                in: scope
            )
        )
    }

    func testViewingSessionOnlyClearsMatchingNotification() {
        let scope = DeliveredNotificationScope.session(id: "session-123")

        XCTAssertTrue(
            NotificationManager.shouldClearDeliveredNotification(
                categoryIdentifier: "BOOTH_CALL",
                userInfo: ["session_id": "session-123"],
                in: scope
            )
        )
        XCTAssertFalse(
            NotificationManager.shouldClearDeliveredNotification(
                categoryIdentifier: "BOOTH_CALL",
                userInfo: ["session_id": "session-456"],
                in: scope
            )
        )
    }

    func testViewingDashboardClearsCallNotifications() {
        XCTAssertTrue(
            NotificationManager.shouldClearDeliveredNotification(
                categoryIdentifier: "BOOTH_CALL",
                userInfo: [:],
                in: .allCalls
            )
        )
        XCTAssertFalse(
            NotificationManager.shouldClearDeliveredNotification(
                categoryIdentifier: "BOOTH_MESSAGE",
                userInfo: ["messageId": "message-123"],
                in: .allCalls
            )
        )
    }

    @MainActor
    func testVisibleScopeSuppressesOnlyMatchingForegroundNotifications() {
        let manager = NotificationManager()
        let scopeId = UUID()

        manager.markNotificationScopeVisible(.allMessages, id: scopeId)

        XCTAssertTrue(
            manager.isViewingNotification(
                NotificationManager.deliveredNotificationDescriptor(
                    categoryIdentifier: "BOOTH_MESSAGE",
                    userInfo: ["messageId": "message-123"]
                )
            )
        )
        XCTAssertFalse(
            manager.isViewingNotification(
                NotificationManager.deliveredNotificationDescriptor(
                    categoryIdentifier: "BOOTH_CALL",
                    userInfo: ["sessionId": "session-123"]
                )
            )
        )

        manager.markNotificationScopeHidden(id: scopeId)
        XCTAssertFalse(
            manager.isViewingNotification(
                NotificationManager.deliveredNotificationDescriptor(
                    categoryIdentifier: "BOOTH_MESSAGE",
                    userInfo: ["messageId": "message-123"]
                )
            )
        )
    }

    @MainActor
    func testNotificationManagerForwardsToSharedNavigationStore() {
        let store = AppNavigationStore()
        let manager = NotificationManager(navigationStore: store)

        manager.route(to: .messages(messageId: "message-123"))
        XCTAssertEqual(store.pendingTarget, .messages(.detail(id: "message-123")))
        XCTAssertEqual(manager.navigationTarget, .messages(messageId: "message-123"))

        manager.route(to: .reviewQueue)
        XCTAssertEqual(store.pendingTarget, .messages(.list(filter: .review)))
        XCTAssertEqual(manager.navigationTarget, .reviewQueue)
    }

    @MainActor
    func testSignOutResetClearsPendingNavigation() {
        let store = AppNavigationStore()
        let manager = NotificationManager(navigationStore: store)
        store.route(to: .messages(.detail(id: "previous-account-message")))

        manager.resetForSignOut()

        XCTAssertNil(store.pendingTarget)
    }

    func testRegisterMobileDeviceRequestEncodesAsExpected() throws {
        let req = RegisterMobileDeviceRequest(
            apnsToken: String(repeating: "a", count: 64),
            platform: .ios,
            deviceName: "Test iPhone",
            preferences: MobileDevicePreferences(
                callStarted: false,
                messageReceived: true,
                messageFlagged: true,
                moderationQueueHigh: false
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(req)
        let str = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(str.contains("\"apnsToken\":\""))
        XCTAssertTrue(str.contains("\"platform\":\"ios\""))
        XCTAssertTrue(str.contains("\"deviceName\":\"Test iPhone\""))
        XCTAssertTrue(str.contains("\"callStarted\":false"))
    }

    @MainActor
    func testNotificationManagerInitFromUserDefaults() throws {
        let suiteName = "test-notif-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = MobileDevicePreferences(
            callStarted: false,
            messageReceived: true,
            messageFlagged: false,
            moderationQueueHigh: true
        )
        let encoded = try JSONEncoder().encode(prefs)
        defaults.set(encoded, forKey: "notifications.preferences")
        defaults.set("device-123", forKey: "notifications.deviceId")
        defaults.set("token-abc", forKey: "notifications.apnsToken")

        let manager = NotificationManager(defaults: defaults)
        XCTAssertEqual(manager.preferences, prefs)
        XCTAssertEqual(manager.deviceId, "device-123")
        XCTAssertEqual(manager.apnsToken, "token-abc")
    }

    @MainActor
    func testNotificationManagerInitWithoutPersistedStateUsesDefaults() throws {
        let suiteName = "test-notif-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = NotificationManager(defaults: defaults)
        XCTAssertEqual(manager.preferences, .defaults)
        XCTAssertNil(manager.deviceId)
        XCTAssertNil(manager.apnsToken)
    }

    @MainActor
    func testRapidPreferenceUpdatesCoalesceToFinalState() async throws {
        let suiteName = "test-notif-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // No deviceId → no network calls, but coalescing still applies locally.
        let manager = NotificationManager(
            defaults: defaults,
            debounceInterval: .milliseconds(50)
        )

        // Simulate rapid toggles on multiple preferences.
        await manager.updatePreference(\.callStarted, to: false)
        await manager.updatePreference(\.messageReceived, to: false)
        await manager.updatePreference(\.callStarted, to: true)
        await manager.updatePreference(\.moderationQueueHigh, to: true)

        // Final local state must reflect the last value for each key path.
        XCTAssertTrue(manager.preferences.callStarted)
        XCTAssertFalse(manager.preferences.messageReceived)
        XCTAssertTrue(manager.preferences.messageFlagged)
        XCTAssertTrue(manager.preferences.moderationQueueHigh)

        // Persisted preferences match the final state.
        let data = try XCTUnwrap(defaults.data(forKey: "notifications.preferences"))
        let persisted = try JSONDecoder().decode(MobileDevicePreferences.self, from: data)
        XCTAssertEqual(persisted, manager.preferences)
    }
}
