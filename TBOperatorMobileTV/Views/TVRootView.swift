//
//  TVRootView.swift
//  TBOperatorMobileTV
//

import SwiftUI

struct TVRootView: View {
    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.extraLarge) {
                Image(systemName: "phone.connection")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .foregroundStyle(Theme.Colors.accent)

                Text("Telephone-Booth Operator")
                    .font(Theme.Fonts.headerXL())
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Please hold for the operator.")
                    .font(Theme.Fonts.bodyLarge)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}

#Preview {
    TVRootView()
}
