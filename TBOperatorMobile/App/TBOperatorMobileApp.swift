//
//  TBOperatorMobileApp.swift
//  TBOperatorMobile (iOS / iPadOS)
//

import SwiftUI

@main
struct TBOperatorMobileApp: App {
    @UIApplicationDelegateAdaptor(TBOperatorAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
