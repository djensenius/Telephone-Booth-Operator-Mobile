//
//  AuthError.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

/// Errors surfaced by `AuthManager`.
public enum AuthError: Error, LocalizedError {
    case noCode
    case stateMismatch
    case tokenExchangeFailed(String)
    case cancelled
    case unsupportedPlatform
    case unknown
    /// Server explicitly rejected the refresh token (4xx). Session is dead;
    /// caller must surface a fresh sign-in flow to the user.
    case refreshTokenInvalid(String)
    /// Refresh failed for a transient reason (offline, DNS, 5xx). Caller
    /// should keep the cached tokens and retry later.
    case transientRefreshFailure(Error)
    /// The device-code authorization request failed to even start.
    case deviceAuthorizationFailed(String)
    /// The user denied authorization on the verification page.
    case deviceAuthorizationDenied
    /// The device code expired before the user finished signing in.
    case deviceCodeExpired
    /// ASWebAuthenticationSession failed to present (start() returned false).
    case presentationFailed

    public var errorDescription: String? {
        switch self {
        case .noCode:
            return "No authorization code received."
        case .stateMismatch:
            return "Authentication response did not match the request."
        case .tokenExchangeFailed(let msg):
            return "Token exchange failed: \(msg)"
        case .cancelled:
            return "Sign-in was cancelled."
        case .unsupportedPlatform:
            return "Sign-in is not supported on this platform yet. Use a paired iPhone, iPad, or Mac."
        case .unknown:
            return "An unknown error occurred."
        case .refreshTokenInvalid(let msg):
            return "Session expired: \(msg)"
        case .transientRefreshFailure(let err):
            return "Temporary refresh failure: \(err.localizedDescription)"
        case .deviceAuthorizationFailed(let msg):
            return "Couldn't start device sign-in: \(msg)"
        case .deviceAuthorizationDenied:
            return "Authorization was denied on the verification page."
        case .deviceCodeExpired:
            return "The sign-in code expired. Please try again."
        case .presentationFailed:
            return "Unable to present the sign-in window. Please try again."
        }
    }
}
