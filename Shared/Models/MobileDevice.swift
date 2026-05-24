//
//  MobileDevice.swift
//  TelephoneBoothOperatorMobile
//
//  Codable mirrors of the operator's MobileDevice + preference schemas.
//

import Foundation

public enum MobileDevicePlatform: String, Codable, Sendable, CaseIterable {
    case ios
    case ipados
    case macos
    case watchos
    case visionos
    case tvos

    /// The platform string for the currently-compiled target. Distinguishing
    /// iPhone vs iPad is done at runtime by callers; this returns `ios` on
    /// both iPhone and iPad builds and lets the caller upgrade to `ipados`
    /// where appropriate.
    public static var current: MobileDevicePlatform {
        #if os(visionOS)
        return .visionos
        #elseif os(watchOS)
        return .watchos
        #elseif os(tvOS)
        return .tvos
        #elseif os(macOS)
        return .macos
        #else
        return .ios
        #endif
    }
}

public struct MobileDevicePreferences: Codable, Equatable, Sendable {
    public var callStarted: Bool
    public var messageReceived: Bool
    public var messageFlagged: Bool
    public var moderationQueueHigh: Bool

    public init(
        callStarted: Bool = true,
        messageReceived: Bool = true,
        messageFlagged: Bool = true,
        moderationQueueHigh: Bool = false
    ) {
        self.callStarted = callStarted
        self.messageReceived = messageReceived
        self.messageFlagged = messageFlagged
        self.moderationQueueHigh = moderationQueueHigh
    }

    public static let defaults = MobileDevicePreferences()
}

public struct MobileDevice: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let apnsToken: String
    public let platform: MobileDevicePlatform
    public let deviceName: String?
    public let preferences: MobileDevicePreferences
    public let registeredAt: Date
    public let lastSeenAt: Date
}

public struct RegisterMobileDeviceRequest: Codable, Sendable {
    public let apnsToken: String
    public let platform: MobileDevicePlatform
    public let deviceName: String?
    public let preferences: MobileDevicePreferences?

    public init(
        apnsToken: String,
        platform: MobileDevicePlatform = .current,
        deviceName: String? = nil,
        preferences: MobileDevicePreferences? = nil
    ) {
        self.apnsToken = apnsToken
        self.platform = platform
        self.deviceName = deviceName
        self.preferences = preferences
    }
}

public struct UpdateMobileDevicePreferencesRequest: Codable, Sendable {
    public let deviceName: String?
    public let preferences: MobileDevicePreferences?

    public init(deviceName: String? = nil, preferences: MobileDevicePreferences? = nil) {
        self.deviceName = deviceName
        self.preferences = preferences
    }
}
