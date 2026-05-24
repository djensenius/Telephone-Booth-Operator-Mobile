//
//  TBOperatorMobileWatchApp.swift
//  TBOperatorMobileWatch
//

import SwiftUI

@main
struct TBOperatorMobileWatchApp: App {
    @WKApplicationDelegateAdaptor(TBOperatorWatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
