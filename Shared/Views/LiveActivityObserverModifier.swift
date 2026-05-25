//
//  LiveActivityObserverModifier.swift
//  TelephoneBoothOperatorMobile
//
//  View modifier that starts/stops the LiveActivityEventObserver
//  alongside the view lifecycle. Applied to the signed-in root so
//  call events produce Live Activities while the user is authenticated.
//

import SwiftUI

#if canImport(ActivityKit) && !os(macOS)
private struct LiveActivityObserverModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                LiveActivityEventObserver.shared.start()
            }
            .onDisappear {
                LiveActivityEventObserver.shared.stop()
            }
    }
}
#endif

extension View {
    @ViewBuilder
    func liveActivityObserver() -> some View {
        #if canImport(ActivityKit) && !os(macOS)
        self.modifier(LiveActivityObserverModifier())
        #else
        self
        #endif
    }
}
