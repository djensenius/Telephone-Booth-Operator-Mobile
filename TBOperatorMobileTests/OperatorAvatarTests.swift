//
//  OperatorAvatarTests.swift
//  TBOperatorMobileTests
//

import XCTest
@testable import TBOperatorMobile

final class OperatorAvatarTests: XCTestCase {
    func testOperatorMePrefersProviderPictureForAvatar() throws {
        let profile = OperatorMe(
            id: "auth0|operator-1",
            name: "Ada Lovelace",
            email: "ada@example.com",
            groups: [],
            picture: URL(string: "https://example.com/avatar.png"),
            providerName: "Authentik"
        )

        XCTAssertEqual(profile.avatarURL?.host, "example.com")
        XCTAssertEqual(profile.avatarURL?.path, "/avatar.png")
    }

    func testOperatorMeGravatarFallback() throws {
        let profile = OperatorMe(
            id: "auth0|operator-1",
            name: "Ada Lovelace",
            email: " Ada@Example.com ",
            groups: [],
            providerName: "Authentik"
        )

        XCTAssertEqual(profile.avatarURL?.host, "www.gravatar.com")
        XCTAssertEqual(
            profile.avatarURL?.path,
            "/avatar/b5fc85e55755f9e0d030a10ab4429b6b2944855f9a0d60077fe832becbc41d72"
        )
        XCTAssertEqual(profile.avatarURL?.query, "d=404&s=160")
    }
}
