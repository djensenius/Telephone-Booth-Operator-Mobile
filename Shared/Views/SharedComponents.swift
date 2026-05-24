//
//  SharedComponents.swift
//  TelephoneBoothOperatorMobile
//
//  Small SwiftUI primitives reused across Status, Sessions, System, and
//  later feature surfaces. Keeping them in one place prevents implicit
//  coupling between feature folders.
//

import SwiftUI

/// Uppercased section caption used at the top of each dashboard card.
public struct SectionHeader: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .font(Theme.Fonts.caption.weight(.semibold))
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

/// Label / value pair rendered as a key/value row.
public struct StatRow: View {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack {
            Text(label)
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(value)
                .font(Theme.Fonts.bodyMedium.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }
}

public enum BannerKind {
    case error, info

    public var color: Color {
        switch self {
        case .error: return Theme.Colors.error
        case .info: return Theme.Colors.info
        }
    }

    public var icon: String {
        switch self {
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

/// Compact inline banner for surface-level errors and notices.
public struct BannerView: View {
    public let message: String
    public let kind: BannerKind

    public init(message: String, kind: BannerKind) {
        self.message = message
        self.kind = kind
    }

    public var body: some View {
        Label(message, systemImage: kind.icon)
            .foregroundStyle(kind.color)
            .font(Theme.Fonts.bodySmall)
            .padding(Theme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardBackground()
    }
}

public extension View {
    /// `.refreshable` is unavailable on tvOS. Apply it where supported,
    /// no-op elsewhere.
    @ViewBuilder
    func refreshableIfAvailable(_ action: @escaping @Sendable () async -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        self.refreshable(action: action)
        #endif
    }
}
