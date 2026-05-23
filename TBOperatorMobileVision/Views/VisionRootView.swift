//
//  VisionRootView.swift
//  TBOperatorMobileVision
//

import SwiftUI

struct VisionRootView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: "phone.connection")
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)
                .foregroundStyle(Theme.Colors.accent)

            Text("Telephone-Booth Operator")
                .font(Theme.Fonts.headerXL())
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Please hold for the operator.")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.extraLarge)
        .frame(minWidth: 640, minHeight: 480)
        .glassBackgroundEffect()
    }
}

#Preview {
    VisionRootView()
}
