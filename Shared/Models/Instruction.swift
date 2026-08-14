//
//  Instruction.swift
//  TelephoneBoothOperatorMobile
//
//  Global instruction clips managed by operators. Every active clip is
//  eligible for random playback when a caller dials zero.
//

import Foundation

public enum InstructionStatus: Codable, Sendable, Hashable {
    case active
    case inactive
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .active: return "active"
        case .inactive: return "inactive"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "active": self = .active
        case "inactive": self = .inactive
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayName: String { rawValue.capitalized }
}

public struct Instruction: Codable, Sendable, Equatable, Identifiable {
    public static let descriptionMaxLength = 280

    public let id: String
    public let description: String?
    public let status: InstructionStatus
    public let createdAt: Date
    public let audio: AudioRef

    public init(
        id: String,
        description: String?,
        status: InstructionStatus,
        createdAt: Date,
        audio: AudioRef
    ) {
        self.id = id
        self.description = description
        self.status = status
        self.createdAt = createdAt
        self.audio = audio
    }
}

public struct InstructionList: Codable, Sendable, Equatable {
    public let items: [Instruction]
    public let nextCursor: String?

    public init(items: [Instruction], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

public struct InstructionCreate: Codable, Sendable, Equatable {
    public let description: String?
    public let audioFileId: String
    public let status: InstructionStatus?

    public init(description: String?, audioFileId: String, status: InstructionStatus? = nil) {
        self.description = description
        self.audioFileId = audioFileId
        self.status = status
    }
}

public struct InstructionUpdate: Codable, Sendable, Equatable {
    public let description: String?

    public init(description: String?) {
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let description {
            try container.encode(description, forKey: .description)
        } else {
            try container.encodeNil(forKey: .description)
        }
    }
}
