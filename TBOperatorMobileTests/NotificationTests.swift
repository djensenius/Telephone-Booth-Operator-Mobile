//
//  NotificationTests.swift
//

import XCTest
@testable import TBOperatorMobile

final class NotificationTests: XCTestCase {
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
}
