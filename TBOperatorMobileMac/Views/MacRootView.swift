//
//  MacRootView.swift
//  TBOperatorMobileMac
//

import SwiftUI

struct MacRootView: View {
    var demoMode = false

    var body: some View {
        RootContainerView(demoMode: demoMode)
            .frame(minWidth: 760, minHeight: 480)
            .containerBackground(for: .window) {
                ZStack {
                    Theme.Colors.background
                    RadialGradient(
                        colors: [Theme.Colors.accent.opacity(0.08), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 560
                    )
                }
            }
    }
}

#Preview {
    MacRootView(demoMode: true)
}
