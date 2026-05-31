//
//  RootView.swift
//  TBOperatorMobile
//
//  Thin platform shell — all logic lives in `Shared/Views/RootContainerView.swift`.
//

import SwiftUI

struct RootView: View {
    var demoMode = false

    var body: some View {
        RootContainerView(demoMode: demoMode)
    }
}

#Preview {
    RootView(demoMode: true)
}
