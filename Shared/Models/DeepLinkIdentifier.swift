//
//  DeepLinkIdentifier.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

/// Stable identifiers for the signed-in tabs, used for selection, compact
/// overflow navigation, deep links, and screenshot automation.
enum OperatorTab: String, Hashable {
    case dashboard, stats, sessions, messages
    case thermals, events, questions, instructions, audit, system, settings
    case more

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .stats: return "Stats"
        case .sessions: return "Sessions"
        case .messages: return "Messages"
        case .thermals: return "Thermals"
        case .events: return "Events"
        case .questions: return "Questions"
        case .instructions: return "Instructions"
        case .audit: return "Audit"
        case .system: return "System"
        case .settings: return "Settings"
        case .more: return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
        case .stats: return "chart.bar.fill"
        case .sessions: return "phone.connection.fill"
        case .messages: return "tray.full"
        case .thermals: return "thermometer.variable.and.figure"
        case .events: return "antenna.radiowaves.left.and.right"
        case .questions: return "questionmark.bubble"
        case .instructions: return "phone.badge.waveform"
        case .audit: return "list.bullet.rectangle.portrait"
        case .system: return "cpu"
        case .settings: return "gearshape"
        case .more: return "ellipsis"
        }
    }

    static let compactPrimaryNavigationOrder: [OperatorTab] = [
        .dashboard,
        .stats,
        .sessions,
        .messages
    ]

    static func sharedNavigationOrder(
        isAdmin: Bool,
        includesSettings: Bool
    ) -> [OperatorTab] {
        var tabs: [OperatorTab] = [
            .dashboard,
            .stats,
            .sessions,
            .messages,
            .thermals,
            .events,
            .questions
        ]
        if isAdmin {
            tabs.append(contentsOf: [.instructions, .audit])
        }
        tabs.append(.system)
        if includesSettings {
            tabs.append(.settings)
        }
        return tabs
    }

    static func compactMoreNavigationOrder(isAdmin: Bool) -> [OperatorTab] {
        Array(
            sharedNavigationOrder(isAdmin: isAdmin, includesSettings: true)
                .dropFirst(compactPrimaryNavigationOrder.count)
        )
    }

    static func televisionNavigationOrder(isAdmin: Bool) -> [OperatorTab] {
        var tabs: [OperatorTab] = [
            .dashboard, .stats, .sessions, .thermals, .events
        ]
        if isAdmin { tabs.append(.audit) }
        return tabs + [.system, .settings]
    }

    var isCompactPrimary: Bool {
        Self.compactPrimaryNavigationOrder.contains(self)
    }

    var isCompactMoreDestination: Bool {
        !isCompactPrimary && self != .more
    }
}

enum DeepLinkIdentifier {
    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(trimmed) else { return nil }
        return trimmed
    }

    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value != ".",
              value != "..",
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return false
        }
        return !value.contains("/") && !value.contains("\\")
            && !value.contains("?") && !value.contains("#")
    }
}
