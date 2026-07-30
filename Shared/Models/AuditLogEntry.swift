//
//  AuditLogEntry.swift
//  TelephoneBoothOperatorMobile
//
//  The operator's audit trail: one entry per write action, recording who
//  did it, from where, and when. Mirrors `/v1/audit-logs` in the operator
//  API. Admin-only on the server.
//

import Foundation

/// What kind of principal took an action.
///
/// The operator may add actor types without a client release, so unknown
/// values decode into `.unknown` rather than failing the whole page.
public enum AuditActorType: RawRepresentable, Codable, Sendable, Hashable {
    /// A signed-in operator.
    case operatorUser
    /// A phone-side or worker API token.
    case apiToken
    /// No credentials were presented.
    case anonymous
    /// The API itself, for background jobs.
    case system
    /// An actor type this build does not know about.
    case unknown(String)

    /// The actor types this build can name, in filter order.
    public static let knownCases: [AuditActorType] = [
        .operatorUser, .apiToken, .anonymous, .system
    ]

    // MARK: - Raw value mapping

    public var rawValue: String {
        switch self {
        case .operatorUser: return "operator"
        case .apiToken: return "apiToken"
        case .anonymous: return "anonymous"
        case .system: return "system"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "operator": self = .operatorUser
        case "apiToken": self = .apiToken
        case "anonymous": self = .anonymous
        case "system": self = .system
        default: self = .unknown(rawValue)
        }
    }

    // MARK: - Codable

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // MARK: - Presentation

    /// Short label for lists and filter chips.
    public var label: String {
        switch self {
        case .operatorUser: "Operator"
        case .apiToken: "Token"
        case .anonymous: "Anonymous"
        case .system: "System"
        case .unknown(let value): value
        }
    }

    /// SF Symbol shown beside the actor.
    public var symbolName: String {
        switch self {
        case .operatorUser: "person.fill"
        case .apiToken: "key.fill"
        case .anonymous: "questionmark.circle"
        case .system: "gearshape.fill"
        case .unknown: "questionmark.square.dashed"
        }
    }
}

/// A decoded JSON value, used for the small action-specific `metadata` blob.
///
/// The operator deliberately keeps metadata free-form, so there is no fixed
/// shape to model. It never carries transcript text or secrets.
public enum AuditMetadataValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([AuditMetadataValue])
    case object([String: AuditMetadataValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AuditMetadataValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AuditMetadataValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported audit metadata value"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Whole numbers render without a decimal point; counts and byte sizes
    /// are the common case and `184320.0` reads badly.
    private static func numberString(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    /// Compact one-line rendering for the detail rows.
    public var displayString: String {
        switch self {
        case .string(let value): value
        case .bool(let value): value ? "yes" : "no"
        case .null: "—"
        case .number(let value): Self.numberString(value)
        case .array(let values):
            values.map(\.displayString).joined(separator: ", ")
        case .object(let values):
            values
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.displayString)" }
                .joined(separator: ", ")
        }
    }
}

// `ip` is below SwiftLint's minimum identifier length, but it is the name the
// operator API uses on the wire and renaming it would only add a CodingKey.
// swiftlint:disable identifier_name

/// A single recorded write action.
public struct AuditLogEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    /// Stable action name, e.g. `message.approve`.
    public let action: String
    /// What was acted on, when the handler names a target.
    public let targetType: String?
    public let targetId: String?
    public let actorType: AuditActorType
    /// The operator that acted, if any and still present.
    public let actorUserId: String?
    /// The API token that acted, if any and still present.
    public let actorTokenId: String?
    /// Actor name captured at the time of the action, so it survives deletion.
    public let actorLabel: String
    /// Client address the action came from.
    public let ip: String?
    public let userAgent: String?
    public let method: String
    public let path: String
    /// Response status, so the outcome is part of the record.
    public let statusCode: Int
    /// Small action-specific detail; never carries secrets or transcript text.
    public let metadata: [String: AuditMetadataValue]?
    public let createdAt: Date

    public init(
        id: String,
        action: String,
        targetType: String? = nil,
        targetId: String? = nil,
        actorType: AuditActorType,
        actorUserId: String? = nil,
        actorTokenId: String? = nil,
        actorLabel: String,
        ip: String? = nil,
        userAgent: String? = nil,
        method: String,
        path: String,
        statusCode: Int,
        metadata: [String: AuditMetadataValue]? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.action = action
        self.targetType = targetType
        self.targetId = targetId
        self.actorType = actorType
        self.actorUserId = actorUserId
        self.actorTokenId = actorTokenId
        self.actorLabel = actorLabel
        self.ip = ip
        self.userAgent = userAgent
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.metadata = metadata
        self.createdAt = createdAt
    }

    /// Whether the request the entry describes succeeded. A sign-in redirects,
    /// so anything below 400 counts.
    public var succeeded: Bool { statusCode < 400 }

    /// Human-readable action, e.g. `message.approve` → "Message approve",
    /// `apiToken.revoke` → "Api token revoke".
    public var actionTitle: String {
        let words = action.split(separator: ".").flatMap(Self.splitCamelCase)
        guard let first = words.first else { return action }
        let capitalized = first.prefix(1).uppercased() + first.dropFirst()
        return ([capitalized] + words.dropFirst()).joined(separator: " ")
    }

    /// `apiToken` → `["api", "token"]`.
    private static func splitCamelCase(_ part: Substring) -> [String] {
        var words: [String] = []
        for character in part {
            if character.isUppercase || words.isEmpty {
                words.append(String(character).lowercased())
            } else {
                words[words.count - 1].append(character)
            }
        }
        return words
    }
}

// swiftlint:enable identifier_name

/// One page of audit entries, newest first.
public struct AuditLogPage: Codable, Sendable, Equatable {
    public let items: [AuditLogEntry]
    public let nextCursor: String?

    public init(items: [AuditLogEntry], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}
