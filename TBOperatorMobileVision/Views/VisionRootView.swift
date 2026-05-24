//
//  VisionRootView.swift
//  TBOperatorMobileVision
//

import SwiftUI

struct VisionRootView: View {
    var body: some View {
        RootContainerView()
            .frame(minWidth: 640, minHeight: 480)
            .glassBackgroundEffect()
    }
}

#Preview {
    VisionRootView()
}
