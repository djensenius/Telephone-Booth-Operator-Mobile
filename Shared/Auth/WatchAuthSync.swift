//
//  WatchAuthSync.swift
//  TelephoneBoothOperatorMobile
//
//  The phone owns the rotating refresh token. The watch pulls only an access
//  token over the paired-device channel; credentials are never queued.
//

#if os(iOS) || os(watchOS)

import Foundation
import Observation
import WatchConnectivity
import os
#if os(iOS)
import UIKit
#endif

private let watchSyncLogger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "WatchAuthSync"
)

// WCSession's reply closure is not Sendable. It is invoked exactly once on
// the main actor, with a fresh dictionary containing only primitive values.
private final class ReplyBox: @unchecked Sendable {
    let handler: ([String: Any]) -> Void
    init(_ handler: @escaping ([String: Any]) -> Void) { self.handler = handler }
}

enum WatchBrokerReply: Sendable {
    case token(accessToken: String, expiry: Double, issuer: String, clientID: String, apiBase: String)
    case failure(WatchBrokerFailure)

    init(message: [String: Any]) {
        guard message["tbo_ok"] as? Bool == true else {
            self = .failure(WatchBrokerFailure(rawValue: message["reason"] as? String ?? "") ?? .unavailable)
            return
        }
        guard let token = message["access_token"] as? String,
              let expiry = message["expiry"] as? Double,
              let issuer = message["iss"] as? String,
              let clientID = message["cid"] as? String,
              let apiBase = message["api_base"] as? String else {
            self = .failure(.updatePhone)
            return
        }
        self = .token(accessToken: token, expiry: expiry, issuer: issuer, clientID: clientID, apiBase: apiBase)
    }
}

enum WatchBrokerFailure: String, Sendable {
    case unreachable
    case signedOut = "signed_out"
    case demoMode = "demo_mode"
    case unavailable
    case timeout
    case configuration
    case storage
    case updatePhone

    var message: String {
        switch self {
        case .unreachable:
            return "Keep your iPhone nearby, unlock it, and open Operator. Then try again."
        case .signedOut:
            return "Sign in to Operator on your iPhone, then tap Connect to iPhone."
        case .demoMode:
            return "Exit Demo Mode and sign in to Operator on your iPhone."
        case .unavailable:
            return "Your iPhone couldn't renew the session. Check its internet connection and try again."
        case .timeout:
            return "Your iPhone didn't reply. Open Operator on your iPhone and try again."
        case .configuration:
            return "The phone and watch use different server or sign-in settings. Check Settings on both devices."
        case .storage:
            return "Couldn't save the session. Unlock your watch and try again."
        case .updatePhone:
            return "Update Operator on your iPhone and watch, then try again."
        }
    }
}

/// Serializes reply/error/timeout completion, including late WCSession replies.
@MainActor
final class WatchBrokerReplyWaiter {
    private var continuation: CheckedContinuation<WatchBrokerReply, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<WatchBrokerReply, Never>, timeout: Duration) {
        self.continuation = continuation
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
                self?.finish(.failure(.timeout))
            } catch is CancellationError {
                // A reply completed the waiter before its deadline.
            } catch {
                self?.finish(.failure(.unavailable))
            }
        }
    }

    func finish(_ reply: WatchBrokerReply) {
        let pending = continuation
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        pending?.resume(returning: reply)
    }
}

@MainActor
@Observable
public final class WatchAuthSync: NSObject {
    public static let shared = WatchAuthSync()
    static let autoSignInPausedKey = "TBOperatorWatchAutoSignInPaused"

    public private(set) var isConnecting = false
    public private(set) var connectionRevision = 0
    public private(set) var statusMessage: String?

    private nonisolated static let requestKey = "tbo_req"
    private nonisolated static let requestValue = "access_token"
    @ObservationIgnored private var pendingRequest: Task<Bool, Never>?
    @ObservationIgnored private var pendingRequestIsForced = false
    @ObservationIgnored private var requestRevision = 0
    @ObservationIgnored private var injectedAuth: AuthManager?
    @ObservationIgnored private var requestOverride: (@MainActor (Bool) async -> WatchBrokerReply)?

    private var auth: AuthManager { injectedAuth ?? .shared }

    private override init() { super.init() }

    init(auth: AuthManager, request: @escaping @MainActor (Bool) async -> WatchBrokerReply) {
        injectedAuth = auth
        requestOverride = request
        super.init()
    }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState == .notActivated { session.activate() }
    }

    func connectFromLogin(automatically: Bool) async {
        guard !AppConfig.shared.isDemoMode, !LaunchEnv.isScreenshotDemo else { return }
        if automatically, auth.getKeychainItem(account: "oidc_refresh_token") != nil { return }
        #if os(watchOS)
        if automatically, UserDefaults.standard.bool(forKey: Self.autoSignInPausedKey) { return }
        if !automatically {
            UserDefaults.standard.set(false, forKey: Self.autoSignInPausedKey)
        }
        #endif
        _ = await ensureBrokeredToken()
    }

    /// forceRefresh bypasses both caches for a reactive HTTP 401 retry.
    public func ensureBrokeredToken(forceRefresh: Bool = false) async -> Bool {
        guard !AppConfig.shared.isDemoMode, !LaunchEnv.isScreenshotDemo else { return false }
        #if os(watchOS)
        if auth.getAccessToken() == nil,
           UserDefaults.standard.bool(forKey: Self.autoSignInPausedKey) { return false }
        #endif
        if let pendingRequest {
            let needsForcedRequest = forceRefresh && !pendingRequestIsForced
            let revision = requestRevision
            let result = await pendingRequest.value
            guard needsForcedRequest, result else { return result }
            if requestRevision == revision {
                self.pendingRequest = nil
            }
            return await ensureBrokeredToken(forceRefresh: true)
        }
        if !forceRefresh, auth.getAccessToken() != nil, !auth.isTokenExpiringSoon() {
            auth.sessionRestored()
            return true
        }
        isConnecting = true
        statusMessage = nil
        requestRevision &+= 1
        let revision = requestRevision
        let generation = auth.sessionGeneration
        let apiBase = AppConfig.shared.apiBaseURL
        let task = Task { @MainActor in
            let reply: WatchBrokerReply
            if let requestOverride {
                reply = await requestOverride(forceRefresh)
            } else {
                reply = await requestFreshToken(forceRefresh: forceRefresh)
            }
            guard generation == auth.sessionGeneration,
                  apiBase == AppConfig.shared.apiBaseURL,
                  !AppConfig.shared.isDemoMode else { return false }
            return apply(reply)
        }
        pendingRequest = task
        pendingRequestIsForced = forceRefresh
        let success = await task.value
        if requestRevision == revision {
            pendingRequest = nil
            isConnecting = false
        }
        return success
    }

    private func apply(_ reply: WatchBrokerReply) -> Bool {
        switch reply {
        case let .token(accessToken, expiry, issuer, clientID, apiBase):
            let config = AppConfig.shared
            guard issuer.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    == config.oidcIssuerBase.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                  clientID == config.oidcClientID,
                  URL(string: apiBase) == config.apiBaseURL else {
                statusMessage = WatchBrokerFailure.configuration.message
                return false
            }
            guard !accessToken.isEmpty, expiry.isFinite, expiry > Date().timeIntervalSince1970 else {
                statusMessage = WatchBrokerFailure.unavailable.message
                return false
            }
            guard auth.applyBrokeredAccessToken(accessToken: accessToken, expiry: expiry) else {
                statusMessage = WatchBrokerFailure.storage.message
                return false
            }
            return true
        case .failure(let failure):
            statusMessage = failure.message
            if failure == .signedOut { auth.signOut() }
            return false
        }
    }

    private func requestFreshToken(forceRefresh: Bool) async -> WatchBrokerReply {
        guard WCSession.isSupported() else { return .failure(.unreachable) }
        activate()
        let session = WCSession.default
        // Activation is asynchronous; first-launch requests must not fail just
        // because the app delegate and login view started in the same run loop.
        for _ in 0..<25 {
            if session.activationState == .activated { break }
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return .failure(.unavailable)
            }
        }
        guard session.activationState == .activated else {
            return .failure(.unreachable)
        }
        // Sending from the active watch can wake the phone app. A preflight
        // isReachable check would prevent that wake-up; let delivery report failure.
        return await withCheckedContinuation { continuation in
            let waiter = WatchBrokerReplyWaiter(continuation, timeout: .seconds(30))
            session.sendMessage(
                [Self.requestKey: Self.requestValue, "force_refresh": forceRefresh],
                replyHandler: { message in
                    let reply = WatchBrokerReply(message: message)
                    Task { @MainActor in waiter.finish(reply) }
                },
                errorHandler: { _ in
                    Task { @MainActor in waiter.finish(.failure(.unreachable)) }
                }
            )
        }
    }
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
        Task { @MainActor in connectionRevision &+= 1 }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in connectionRevision &+= 1 }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

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
        let forceRefresh = message["force_refresh"] as? Bool ?? false
        Task { @MainActor in
            let config = AppConfig.shared
            let apiBase = config.apiBaseURL
            let auth = AuthManager.shared
            if let brokered = await auth.brokerAccessTokenForWatch(forceRefresh: forceRefresh),
               apiBase == config.apiBaseURL {
                box.handler([
                    "tbo_ok": true,
                    "access_token": brokered.accessToken,
                    "expiry": brokered.expiry,
                    "iss": config.oidcIssuerBase,
                    "cid": config.oidcClientID,
                    "api_base": apiBase.absoluteString
                ])
            } else {
                let reason: WatchBrokerFailure
                if config.isDemoMode {
                    reason = .demoMode
                } else if auth.authState == .signedOut, UIApplication.shared.isProtectedDataAvailable {
                    reason = .signedOut
                } else {
                    reason = .unavailable
                }
                box.handler(["tbo_ok": false, "reason": reason.rawValue])
            }
        }
    }
    #endif
}

#endif
