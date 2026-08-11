//
//  BoothStatusLiveModifier.swift
//  TelephoneBoothOperatorMobile
//
//  Starts/stops the live booth-status store alongside screen lifecycle.
//

import SwiftUI

private struct BoothStatusLiveModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.automaticRefreshEnabled) private var automaticRefreshEnabled
    @State private var isStarted = false

    let store: BoothStatusLiveStore

    func body(content: Content) -> some View {
        content
            .onAppear { updateForCurrentPhase() }
            .onDisappear { stopIfNeeded() }
            .onChange(of: scenePhase) { _, _ in updateForCurrentPhase() }
            .onChange(of: automaticRefreshEnabled) { _, _ in updateForCurrentPhase() }
    }

    private func updateForCurrentPhase() {
        if automaticRefreshEnabled, scenePhase != .background {
            guard !isStarted else { return }
            isStarted = true
            store.start()
        } else {
            stopIfNeeded()
        }
    }

    private func stopIfNeeded() {
        guard isStarted else { return }
        isStarted = false
        store.stop()
    }
}

extension View {
    func boothStatusLive(_ store: BoothStatusLiveStore) -> some View {
        modifier(BoothStatusLiveModifier(store: store))
    }
}
