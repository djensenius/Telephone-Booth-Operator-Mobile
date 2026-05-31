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
    }
}

#Preview {
    MacRootView(demoMode: true)
}
