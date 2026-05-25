//
//  MobileDevice.swift
//  TelephoneBoothOperatorMobile
//
//  Codable mirrors of the operator's MobileDevice + preference schemas.
//

import Foundation

public enum MobileDevicePlatform: Codable, Sendable, Hashable {
    case ios
    case ipados
    case macos
    case watchos
    case visionos
    case tvos
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .ios: return "ios"
        case .ipados: return "ipados"
        case .macos: return "macos"
        case .watchos: return "watchos"
        case .visionos: return "visionos"
        case .tvos: return "tvos"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "ios": self = .ios
        case "ipados": self = .ipados
        case "macos": self = .macos
        case "watchos": self = .watchos
        case "visionos": self = .visionos
        case "tvos": self = .tvos
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

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
