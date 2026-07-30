//
//  CurrentUserStore.swift
//  TelephoneBoothOperatorMobile
//
//  Holds the signed-in operator's profile (`/v1/auth/me`) and re-validates it
//  on a timer. A periodic `fetchMe()` is our liveness signal: if it keeps
//  returning 401/403 the account was disabled or deleted upstream and we sign
//  out. A *single* failure is not enough — see `authFailureTolerance` — so a
//  proxy hiccup or a token that expired mid-flight never costs a login.
//
//  Caveat for bearer clients: the mobile app authenticates with an
//  Authentik-issued access token, and the operator API's bearer path currently
//  trusts that token's embedded claims until it expires. So a revoked account
//  is caught here no later than access-token expiry — not necessarily within
//  one poll. Tightening this to per-poll liveness needs the operator API to
//  revalidate bearer principals against the IdP (tracked separately).
//

import Foundation
import os

@Observable
@MainActor
public final class CurrentUserStore {
    public static let shared = CurrentUserStore()

    /// How often to re-confirm the account is still valid while the app is in
    /// the foreground.
    public static let revalidateInterval: Duration = .seconds(120)

    public private(set) var profile: OperatorMe?
    public private(set) var lastError: String?

    /// Consecutive `/v1/auth/me` authorization failures. A single 401/403 is
    /// not proof the account died — a proxy hiccup, a WAF, or a token that
    /// expired mid-flight all look identical from here — so we only sign out
    /// once the API has refused us repeatedly.
    private var consecutiveAuthFailures = 0

    /// Number of consecutive authorization failures tolerated before the
    /// session is torn down (at `revalidateInterval`, ~6 minutes).
    static let authFailureTolerance = 3

    /// Admins may manage questions and export/import data. Fail closed: until
    /// the profile loads (or if it fails), treat the operator as non-admin.
    public var isAdmin: Bool { profile?.isAdmin ?? false }

    private let client: OperatorClient
    private let auth: AuthManager
    private var revalidateTask: Task<Void, Never>?

    private let logger = Logger(
        subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
        category: "CurrentUserStore"
    )

    public init(
        client: OperatorClient = .shared,
        auth: AuthManager = .shared
    ) {
        self.client = client
        self.auth = auth
    }

    /// Load the profile once and (re)start the periodic revalidation loop.
    /// Safe to call from `.task`; repeated calls replace the running loop.
    public func start() {
        revalidateTask?.cancel()
        revalidateTask = Task { [weak self] in
            // Keep only a weak reference across sleeps and promote it
            // transiently for each refresh, so a signed-in shell that never
            // calls stop() doesn't pin this store (and its loop) alive.
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.revalidateInterval)
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }

    public func stop() {
        revalidateTask?.cancel()
        revalidateTask = nil
    }

    /// Fetch `/v1/auth/me`. On success updates `profile`; on an
    /// authorization failure the account is no longer valid, so sign out.
    public func refresh() async {
        // Demo/screenshot clients are never "signed in" via AuthManager but
        // still serve a canned admin profile, so let them load it too.
        let demo = await client.usesDemoData
        guard auth.isSignedIn || demo else { return }
        do {
            profile = try await client.fetchMe()
            lastError = nil
            consecutiveAuthFailures = 0
        } catch OperatorError.unauthorized(let message) {
            consecutiveAuthFailures += 1
            lastError = message.isEmpty ? "Not authorized." : message
            guard consecutiveAuthFailures >= Self.authFailureTolerance else {
                logger.warning("""
                    /v1/auth/me refused (\(self.consecutiveAuthFailures)/\
                    \(Self.authFailureTolerance)) — keeping session: \
                    \(message, privacy: .public)
                    """)
                return
            }
            logger.warning("account no longer valid — signing out: \(message, privacy: .public)")
            auth.signOut()
            profile = nil
        } catch OperatorError.unauthenticated {
            // No usable bearer right now. That happens whenever the device is
            // offline with an expired access token; `AuthManager` still holds
            // the refresh token and signs out on its own if the provider
            // definitively rejects it. Never tear down the session from here.
            lastError = "Reconnecting…"
        } catch {
            // Transient network/decoding failures shouldn't sign the operator
            // out; keep the last known profile and surface the error.
            consecutiveAuthFailures = 0
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
