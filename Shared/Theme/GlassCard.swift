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

    @ViewBuilder
    func operatorListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.inset)
        #elseif os(tvOS)
        self.listStyle(.plain)
            .background(Theme.Colors.background)
        #else
        self.listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
        #endif
    }

    @ViewBuilder
    func operatorListRowBackground() -> some View {
        #if os(macOS)
        self
        #else
        self.listRowBackground(Theme.Colors.secondaryBackground)
        #endif
    }

    @ViewBuilder
    func operatorNavigationBackground() -> some View {
        #if os(iOS)
        self.background(Theme.Colors.background.ignoresSafeArea())
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self.background(Theme.Colors.background)
        #endif
    }
}
