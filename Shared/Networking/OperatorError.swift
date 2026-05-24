//
//  OperatorError.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public enum OperatorError: Error, LocalizedError {
    /// Caller is not signed in (no usable token).
    case unauthenticated
    /// Server returned HTTP 401/403 — token is invalid or the operator lacks access.
    case unauthorized(String)
    /// Server returned a non-2xx response.
    case httpError(status: Int, body: String)
    /// Response body could not be decoded.
    case decoding(Error)
    /// Network transport failure.
    case transport(Error)
    /// Caller invoked the client with an invalid URL.
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Not signed in."
        case .unauthorized(let message):
            return message.isEmpty ? "You don't have access to this resource." : message
        case .httpError(let status, let body):
            return "Server returned \(status). \(body)"
        case .decoding(let error):
            return "Failed to decode server response: \(error.localizedDescription)"
        case .transport(let error):
            return error.localizedDescription
        case .invalidURL:
            return "Invalid request URL."
        }
    }
}
