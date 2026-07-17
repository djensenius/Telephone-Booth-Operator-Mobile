//
//  CurrentUserStore.swift
//  TelephoneBoothOperatorMobile
//
//  Holds the signed-in operator's profile (`/v1/auth/me`) and re-validates it
//  on a timer. The operator API re-checks the Authentik account (group
//  membership, existence) on every request, so a periodic `fetchMe()` is our
//  signal that the account is still valid: if it starts returning 401/403 the
//  account was disabled or deleted upstream and we sign out immediately. This
//  closes the gap where a booth-side account removed in Authentik kept working
//  until the app was relaunched.
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
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.revalidateInterval)
                if Task.isCancelled { break }
                await self.refresh()
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
        guard auth.isSignedIn else { return }
        do {
            profile = try await client.fetchMe()
            lastError = nil
        } catch OperatorError.unauthorized(let message) {
            logger.warning("account no longer valid — signing out: \(message, privacy: .public)")
            auth.signOut()
            profile = nil
        } catch OperatorError.unauthenticated {
            auth.signOut()
            profile = nil
        } catch {
            // Transient network/decoding failures shouldn't sign the operator
            // out; keep the last known profile and surface the error.
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
