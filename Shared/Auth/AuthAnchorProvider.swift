//
//  AuthAnchorProvider.swift
//  TelephoneBoothOperatorMobile
//
//  Cross-platform presentation anchor for ASWebAuthenticationSession.
//  Not built on tvOS (where ASWebAuthenticationSession is unavailable) or
//  on watchOS (where the system handles presentation automatically).
//

#if !os(tvOS) && !os(watchOS)
import AuthenticationServices
import Foundation
import os

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

private let logger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "AuthAnchorProvider"
)

/// Provides a presentation anchor for ASWebAuthenticationSession across
/// iOS, iPadOS, macOS, and visionOS.
final class AuthAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApp.keyWindow ?? NSWindow()
        #elseif canImport(UIKit)
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for windowScene in windowScenes {
            if let key = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return key
            }
            if let first = windowScene.windows.first {
                return first
            }
        }
        // No existing window: create one bound to an available scene.
        // `init(windowScene:)` is the only non-deprecated UIWindow initializer
        // on iOS / visionOS 26, so a window scene is required for the anchor.
        if let windowScene = windowScenes.first {
            logger.warning("No key window found — creating a window for the active scene")
            return UIWindow(windowScene: windowScene)
        }
        // The system only requests a presentation anchor while the app is
        // foregrounded, so at least one window scene is always present here.
        preconditionFailure("No UIWindowScene available to anchor authentication")
        #else
        return ASPresentationAnchor()
        #endif
    }
}
#endif
