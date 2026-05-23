//
//  WatchRootView.swift
//  TBOperatorMobileWatch
//

import SwiftUI

struct WatchRootView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.small) {
            Image(systemName: "phone.connection")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .foregroundStyle(Theme.Colors.accent)

            Text("Operator")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Holding…")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding()
    }
}

#Preview {
    WatchRootView()
}
