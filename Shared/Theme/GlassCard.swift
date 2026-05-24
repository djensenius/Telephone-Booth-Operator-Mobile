//
//  GlassCard.swift
//  TelephoneBoothOperatorMobile
//
//  Reusable Catppuccin-tinted Liquid Glass card surface. visionOS gets
//  the real glass material; every other platform falls back to the
//  Catppuccin elevated surface.
//

import SwiftUI

public extension View {
    @ViewBuilder
    func glassCardBackground(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.Colors.elevatedBackground)
            )
            .modifier(GlassOverlayModifier(cornerRadius: cornerRadius))
    }
}

private struct GlassOverlayModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        #if os(visionOS)
        content
            .glassBackgroundEffect(in: .rect(cornerRadius: cornerRadius))
        #else
        content
        #endif
    }
}
