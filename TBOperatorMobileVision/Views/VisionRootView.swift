//
//  VisionRootView.swift
//  TBOperatorMobileVision
//

import SwiftUI

struct VisionRootView: View {
    var demoMode = false

    var body: some View {
        RootContainerView(demoMode: demoMode)
            .frame(minWidth: 640, minHeight: 480)
            .glassBackgroundEffect()
    }
}

#Preview {
    VisionRootView(demoMode: true)
}
