//
//  RuntimeMode.swift
//  TelephoneBoothOperatorMobile
//
//  Mirrors the operator's `RuntimeModeSchema` (real / mock / simulator).
//  Surfaced in `BoothStatus.runtimeMode` and `BoothSystemSnapshot.runtimeMode`
//  so the UI can flag non-production booths with a small "MOCK" / "SIM" pill.
//
//  Forward-compatible: any unknown raw value round-trips through `.unknown`,
//  matching the pattern used by every other server-side enum in this app.
//

import Foundation

public enum RuntimeMode: Codable, Sendable, Hashable {
    case real
    case mock
    case simulator
    case unknown(String)

    public static let knownCases: [RuntimeMode] = [.real, .mock, .simulator]

    public var rawValue: String {
        switch self {
        case .real: return "real"
        case .mock: return "mock"
        case .simulator: return "simulator"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "real": self = .real
        case "mock": self = .mock
        case "simulator": self = .simulator
        default: self = .unknown(rawValue)
        }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // MARK: - Display helpers

    /// Production booth (real hardware) — the operator treats this as the
    /// default and renders no badge for it.
    public var isReal: Bool {
        if case .real = self { return true }
        return false
    }

    /// Whether this mode should be flagged visually. `real` (or any other
    /// unrecognised future "production" mode) is silent; everything else
    /// gets a pill.
    public var shouldDisplayBadge: Bool { !isReal }

    /// Compact pill label, matching the operator web UI.
    public var shortLabel: String {
        switch self {
        case .real: return "Live"
        case .mock: return "MOCK"
        case .simulator: return "SIM"
        case .unknown(let value): return value.uppercased()
        }
    }

    /// Spoken / human-readable display name.
    public var displayName: String {
        switch self {
        case .real: return "Live"
        case .mock: return "Mock"
        case .simulator: return "Simulator"
        case .unknown(let value): return value.capitalized
        }
    }

    /// Long-form tooltip / accessibility description.
    public var tooltip: String {
        switch self {
        case .real:
            return "This booth is running with real Pi hardware adapters."
        case .mock:
            return "This booth is running with in-memory mock adapters — no rotary phone is connected."
        case .simulator:
            return "This booth is being driven by the interactive simulator TUI."
        case .unknown(let value):
            return "Unknown runtime mode: \(value)"
        }
    }
}
