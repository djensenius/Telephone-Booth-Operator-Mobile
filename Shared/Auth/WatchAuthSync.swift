//
//  WatchAuthSync.swift
//  TelephoneBoothOperatorMobile
//
//  Phone-as-broker authentication handoff between the paired iPhone and the
//  standalone watchOS app, over WatchConnectivity.
//
//  Authentik rotates refresh tokens, so the watch must NOT hold a copy of the
//  phone's refresh token — two devices refreshing the same lineage would
//  invalidate each other. Instead the watch keeps only a short-lived access
//  token and PULLS a fresh one from the phone (which owns the refresh-token
//  lineage) when needed. A watch in "brokered mode" is identified by the
//  absence of a refresh token in its Keychain; the on-watch OIDC login remains
//  available as a fallback when the phone is unreachable.
//

#if os(iOS) || os(watchOS)

import Foundation
import Observation
import WatchConnectivity
import os

private let watchSyncLogger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "WatchAuthSync"
)

/// Bridges WatchConnectivity's non-`Sendable` reply closure into a `@MainActor`
/// task. Genuinely necessary: `WCSession`'s `replyHandler` is not annotated
/// `Sendable`, but we only ever invoke it with a freshly built dictionary of
/// primitives, so the wrapper is safe.
private final class ReplyBox: @unchecked Sendable {
    let handler: ([String: Any]) -> Void
    init(_ handler: @escaping ([String: Any]) -> Void) { self.handler = handler }
}

/// Result of a broker request, carried back across the actor boundary. Only
/// primitive, `Sendable` values cross the hop.
private enum BrokerReply: Sendable {
    case token(accessToken: String, expiry: Double, iss: String, cid: String)
    case failure(reason: String)
}

@MainActor
@Observable
public final class WatchAuthSync: NSObject {
    public static let shared = WatchAuthSync()

    private nonisolated static let requestKey = "tbo_req"
    private nonisolated static let requestValue = "access_token"

    private override init() { super.init() }

    /// Activates the shared `WCSession`. Safe to call multiple times.
    public func activate() {
        guard WCSession.isSupported() else {
            watchSyncLogger.info("WCSession unsupported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    #if os(watchOS)
    /// Ensures the watch has a usable access token, pulling a fresh one from
    /// the paired phone when the cached token is missing or near expiry.
    /// Returns false when the phone is unreachable or signed out.
    public func ensureBrokeredToken() async -> Bool {
        let auth = AuthManager.shared
        if auth.getAccessToken() != nil, !auth.isTokenExpiringSoon() {
            return true
        }
        let reply = await requestFreshToken()
        switch reply {
        case let .token(accessToken, expiry, iss, cid):
            guard iss == AppConfig.shared.oidcIssuerBase,
                  cid == AppConfig.shared.oidcClientID else {
                watchSyncLogger.error("Brokered token issuer/client mismatch — rejecting")
                return false
            }
            return auth.applyBrokeredAccessToken(accessToken: accessToken, expiry: expiry)
        case let .failure(reason):
            watchSyncLogger.info("Broker request failed: \(reason, privacy: .public)")
            if reason == "signed_out" { auth.signOut() }
            return false
        }
    }

    private func requestFreshToken() async -> BrokerReply {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            return .failure(reason: "unreachable")
        }
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                [Self.requestKey: Self.requestValue],
                replyHandler: { reply in
                    if let success = reply["tbo_ok"] as? Bool, success,
                       let token = reply["access_token"] as? String,
                       let expiry = reply["expiry"] as? Double {
                        continuation.resume(returning: .token(
                            accessToken: token,
                            expiry: expiry,
                            iss: reply["iss"] as? String ?? "",
                            cid: reply["cid"] as? String ?? ""
                        ))
                    } else {
                        continuation.resume(returning: .failure(
                            reason: reply["reason"] as? String ?? "unknown"
                        ))
                    }
                },
                errorHandler: { error in
                    continuation.resume(returning: .failure(reason: error.localizedDescription))
                }
            )
        }
    }
    #endif
}

extension WatchAuthSync: WCSessionDelegate {
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            watchSyncLogger.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a newly paired watch can reach the broker.
        WCSession.default.activate()
    }

    /// Phone side: answer the watch's request for a fresh access token. The
    /// refresh token never leaves the phone — only the short-lived access
    /// token and its expiry are returned.
    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard (message[Self.requestKey] as? String) == Self.requestValue else {
            replyHandler(["tbo_ok": false, "reason": "unknown"])
            return
        }
        let box = ReplyBox(replyHandler)
        Task { @MainActor in
            let config = AppConfig.shared
            if let brokered = await AuthManager.shared.brokerAccessTokenForWatch() {
                box.handler([
                    "tbo_ok": true,
                    "access_token": brokered.accessToken,
                    "expiry": brokered.expiry,
                    "iss": config.oidcIssuerBase,
                    "cid": config.oidcClientID
                ])
            } else {
                box.handler(["tbo_ok": false, "reason": "signed_out"])
            }
        }
    }
    #endif
}

#endif
