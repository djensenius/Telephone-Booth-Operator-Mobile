//
//  WatchRootView.swift
//  TBOperatorMobileWatch
//

import SwiftUI

struct WatchRootView: View {
    var demoMode = false

    var body: some View {
        RootContainerView(demoMode: demoMode)
    }
}

#Preview {
    WatchRootView(demoMode: true)
}
