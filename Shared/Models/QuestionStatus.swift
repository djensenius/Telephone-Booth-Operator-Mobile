//
//  QuestionStatus.swift
//  TelephoneBoothOperatorMobile
//
//  Publication lifecycle for a booth question: a freshly uploaded prompt
//  starts as `draft`, becomes `active` once an operator publishes it (only
//  active questions are offered to callers), and `archived` when retired.
//  Mirrors the forward-compatible `.unknown(String)` pattern used by
//  `MessageStatus` so a new server-side state never breaks decoding.
//

import Foundation

public enum QuestionStatus: Codable, Sendable, Hashable {
    case draft
    case active
    case archived
    case unknown(String)

    public static let knownCases: [QuestionStatus] = [.draft, .active, .archived]

    public var rawValue: String {
        switch self {
        case .draft: return "draft"
        case .active: return "active"
        case .archived: return "archived"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "draft": self = .draft
        case "active": self = .active
        case "archived": self = .archived
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayName: String { rawValue.capitalized }
}
