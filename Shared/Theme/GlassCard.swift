//
//  GlassCard.swift
//  TelephoneBoothOperatorMobile
//
//  Reusable card surface. macOS and visionOS render a real Liquid Glass
//  material (`.glassEffect` / `.glassBackgroundEffect`); iOS / iPadOS keep
//  the selected Theme elevated surface so the booth theme reads clearly.
//

import SwiftUI

public extension View {
    @ViewBuilder
    func glassCardBackground(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        #if os(macOS)
        self
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        #elseif os(visionOS)
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.Colors.elevatedBackground)
            )
            .glassBackgroundEffect(in: .rect(cornerRadius: cornerRadius))
        #else
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.Colors.elevatedBackground)
            )
        #endif
    }
}
