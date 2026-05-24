//
//  TBOperatorMobileMacApp.swift
//  TBOperatorMobileMac
//

import SwiftUI

@main
struct TBOperatorMobileMacApp: App {
    @NSApplicationDelegateAdaptor(TBOperatorMacAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MacRootView()
        }
        .windowResizability(.contentSize)
    }
}
