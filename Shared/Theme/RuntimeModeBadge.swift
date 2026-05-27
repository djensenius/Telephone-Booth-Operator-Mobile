//
//  RuntimeModeBadge.swift
//  TelephoneBoothOperatorMobile
//
//  Tiny pill that flags non-production booths. Lives in its own file
//  (rather than SharedComponents.swift) so the widget extension — which
//  only sees `Shared/Models` and `Shared/Theme` — can pull it in
//  without dragging the app-only views along.
//

import SwiftUI

/// Compact pill that flags non-production booths. Renders nothing for
/// `real` (or nil) so callers can drop it inline next to a heading
/// without conditional wrapping. Mirrors the operator web
/// `RuntimeModeBadge`.
public struct RuntimeModeBadge: View {
    public let mode: RuntimeMode?

    public init(mode: RuntimeMode?) {
        self.mode = mode
    }

    public var body: some View {
        if let mode, mode.shouldDisplayBadge {
            Text(mode.shortLabel)
                .font(Theme.Fonts.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    Capsule().fill(color(for: mode))
                }
                .accessibilityLabel(Text("Booth runtime mode: \(mode.displayName)"))
            #if !os(tvOS) && !os(watchOS)
                .help(mode.tooltip)
            #endif
        }
    }

    private func color(for mode: RuntimeMode) -> Color {
        switch mode {
        case .mock: return Theme.Colors.info
        case .simulator: return Theme.Colors.warning
        case .real, .unknown: return Theme.Colors.textSecondary
        }
    }
}
