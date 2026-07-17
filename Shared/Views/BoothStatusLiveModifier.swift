//
//  BoothStatusLiveModifier.swift
//  TelephoneBoothOperatorMobile
//
//  Starts/stops the live booth-status store alongside screen lifecycle.
//

import SwiftUI

private struct BoothStatusLiveModifier: ViewModifier {
    let store: BoothStatusLiveStore

    func body(content: Content) -> some View {
        content
            .onAppear { store.start() }
            .onDisappear { store.stop() }
    }
}

extension View {
    func boothStatusLive(_ store: BoothStatusLiveStore) -> some View {
        modifier(BoothStatusLiveModifier(store: store))
    }
}
