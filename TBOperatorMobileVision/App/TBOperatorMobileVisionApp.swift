//
//  TBOperatorMobileVisionApp.swift
//  TBOperatorMobileVision
//

import SwiftUI

@main
struct TBOperatorMobileVisionApp: App {
    @UIApplicationDelegateAdaptor(TBOperatorAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            VisionRootView()
        }
        .windowStyle(.plain)
    }
}
