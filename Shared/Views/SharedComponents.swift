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

// MARK: - Booth staleness chip

/// Severity levels matching the operator web `BoothStatusBadge`
/// thresholds (fresh < 60 s, warning 60 s – 5 min, offline > 5 min).
public enum BoothStalenessLevel: Sendable {
    case fresh
    case warning
    case offline
}

public enum BoothStalenessThresholds {
    public static let warningSeconds: TimeInterval = 60
    public static let offlineSeconds: TimeInterval = 300
}

/// Pure function for unit testing — given a `lastStatusAt` and the
/// current clock, returns the staleness level and a short label
/// ("Last seen 3m ago" / "Booth offline") or nil when fresh.
public func boothStaleness(
    lastStatusAt: Date?,
    now: Date = Date()
) -> (level: BoothStalenessLevel, label: String?) {
    guard let last = lastStatusAt else { return (.fresh, nil) }
    let elapsed = now.timeIntervalSince(last)
    if elapsed < BoothStalenessThresholds.warningSeconds {
        return (.fresh, nil)
    }
    if elapsed < BoothStalenessThresholds.offlineSeconds {
        let mins = max(1, Int((elapsed / 60).rounded()))
        return (.warning, "Last seen \(mins)m ago")
    }
    return (.offline, "Booth offline")
}

/// Small chip displayed next to the booth state badge when the operator
/// hasn't seen a status update in over a minute. Auto-ticks every 10 s
/// while visible (via `TimelineView`).
public struct BoothStalenessChip: View {
    public let lastStatusAt: Date?

    public init(lastStatusAt: Date?) {
        self.lastStatusAt = lastStatusAt
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let staleness = boothStaleness(lastStatusAt: lastStatusAt, now: context.date)
            if staleness.level != .fresh, let label = staleness.label {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: staleness.level))
                        .frame(width: 8, height: 8)
                    Text(label)
                        .font(Theme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(color(for: staleness.level))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    Capsule().fill(color(for: staleness.level).opacity(0.15))
                }
                .accessibilityLabel(Text(label))
            }
        }
    }

    private func color(for level: BoothStalenessLevel) -> Color {
        switch level {
        case .fresh: return Theme.Colors.success
        case .warning: return Theme.Colors.warning
        case .offline: return Theme.Colors.error
        }
    }
}
