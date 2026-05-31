//
//  TVRootView.swift
//  TBOperatorMobileTV
//

import SwiftUI

struct TVRootView: View {
    var demoMode = false

    var body: some View {
        RootContainerView(demoMode: demoMode)
    }
}

#Preview {
    TVRootView(demoMode: true)
}
