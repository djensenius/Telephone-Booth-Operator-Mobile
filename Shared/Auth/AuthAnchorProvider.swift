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
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let key = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return key
            }
            if let first = windowScene.windows.first {
                return first
            }
        }
        logger.warning("No key window found — falling back to a detached UIWindow")
        return UIWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
#endif
