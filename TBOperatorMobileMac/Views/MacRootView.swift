//
//  MacRootView.swift
//  TBOperatorMobileMac
//

import SwiftUI

struct MacRootView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: "phone.connection")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .foregroundStyle(Theme.Colors.accent)

            Text("Telephone-Booth Operator")
                .font(Theme.Fonts.headerXL())
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Please hold for the operator.")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.extraLarge)
        .frame(minWidth: 480, minHeight: 320)
        .background(Theme.Colors.background)
    }
}

#Preview {
    MacRootView()
}
