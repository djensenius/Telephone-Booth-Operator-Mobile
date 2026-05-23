//
//  RootView.swift
//  TBOperatorMobile
//
//  Placeholder shell. Real auth + tab navigation arrive in PR 2 / PR 3.
//

import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background)
            .navigationTitle("Operator")
        }
    }
}

#Preview {
    RootView()
}
