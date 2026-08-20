//
//  WidgetDeepLink.swift
//  TBOperatorMobileWidgets
//
//  Centralized, read-only deep links. Every widget routes taps through
//  the `tboperator://` URL scheme. Construction is always safe — a
//  malformed identifier degrades to no link rather than a force-unwrap
//  crash — and no link ever triggers a mutating or destructive action.
//

import Foundation

enum WidgetDeepLink {
    private static let scheme = "tboperator"

    static let dashboard = URL(string: "\(scheme)://dashboard")
    static let stats = URL(string: "\(scheme)://stats")
    static let sessions = URL(string: "\(scheme)://sessions")
    static let system = URL(string: "\(scheme)://system")
    static let thermals = URL(string: "\(scheme)://thermals")
    static let messagesReview = URL(string: "\(scheme)://messages?filter=review")

    /// Read-only detail route for a single call session (`View call`).
    /// The parser uses the plural `sessions` host for detail routes.
    static func session(id: String) -> URL? {
        detail(host: "sessions", id: id)
    }

    /// Read-only detail route for a single message.
    /// The parser uses the plural `messages` host for detail routes.
    static func message(id: String) -> URL? {
        detail(host: "messages", id: id)
    }

    private static func detail(host: String, id: String) -> URL? {
        guard let normalized = DeepLinkIdentifier.normalized(id) else { return nil }
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "\(scheme)://\(host)/\(encoded)")
    }
}
