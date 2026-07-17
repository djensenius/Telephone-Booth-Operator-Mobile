//
//  OperatorMe.swift
//  TelephoneBoothOperatorMobile
//
//  Mirrors the `OperatorMe` schema from the operator OpenAPI spec.
//

import Foundation

public struct OperatorMe: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let email: String
    public let groups: [String]
    public let isAdmin: Bool
    public let picture: URL?
    public let providerName: String

    public init(
        id: String,
        name: String,
        email: String,
        groups: [String],
        isAdmin: Bool = false,
        picture: URL? = nil,
        providerName: String
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.groups = groups
        self.isAdmin = isAdmin
        self.picture = picture
        self.providerName = providerName
    }

    // Decode `isAdmin` defensively: older API builds may omit it, in which
    // case the operator is treated as a non-admin (fail-closed).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decode(String.self, forKey: .email)
        groups = try container.decode([String].self, forKey: .groups)
        isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        picture = try container.decodeIfPresent(URL.self, forKey: .picture)
        providerName = try container.decode(String.self, forKey: .providerName)
    }
}
