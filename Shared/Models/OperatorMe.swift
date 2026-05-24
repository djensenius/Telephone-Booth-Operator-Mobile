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
    public let picture: URL?
    public let providerName: String

    public init(
        id: String,
        name: String,
        email: String,
        groups: [String],
        picture: URL? = nil,
        providerName: String
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.groups = groups
        self.picture = picture
        self.providerName = providerName
    }
}
