//
//  AuditLogTests.swift
//
//  Decoding and presentation of the operator audit trail.
//

import XCTest
@testable import TBOperatorMobile

final class AuditLogTests: XCTestCase {

    private let pageJSON = """
    {
      "items": [
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "action": "message.approve",
          "targetType": "message",
          "targetId": "22222222-2222-4222-8222-222222222222",
          "actorType": "operator",
          "actorUserId": "33333333-3333-4333-8333-333333333333",
          "actorTokenId": null,
          "actorLabel": "operator@example.com",
          "ip": "203.0.113.7",
          "userAgent": "TBOperatorMobile/0.2.1",
          "method": "POST",
          "path": "/v1/messages/22222222-2222-4222-8222-222222222222/decision",
          "statusCode": 200,
          "metadata": { "decision": "approve", "previousStatus": "pending" },
          "createdAt": "2026-07-20T12:00:00.000Z"
        },
        {
          "id": "44444444-4444-4444-8444-444444444444",
          "action": "apiToken.revoke",
          "targetType": "apiToken",
          "targetId": "55555555-5555-4555-8555-555555555555",
          "actorType": "apiToken",
          "actorUserId": null,
          "actorTokenId": "55555555-5555-4555-8555-555555555555",
          "actorLabel": "token:booth-main",
          "ip": null,
          "userAgent": null,
          "method": "DELETE",
          "path": "/v1/api-tokens/55555555-5555-4555-8555-555555555555",
          "statusCode": 403,
          "metadata": null,
          "createdAt": "2026-07-20T11:00:00.000Z"
        }
      ],
      "nextCursor": "cursor-1"
    }
    """

    func testAuditPageDecodesActorAttributionAndCursor() throws {
        let page = try OperatorJSON.decoder.decode(AuditLogPage.self, from: Data(pageJSON.utf8))

        XCTAssertEqual(page.nextCursor, "cursor-1")
        XCTAssertEqual(page.items.count, 2)

        let approval = page.items[0]
        XCTAssertEqual(approval.action, "message.approve")
        XCTAssertEqual(approval.actorType, .operatorUser)
        XCTAssertEqual(approval.actorLabel, "operator@example.com")
        XCTAssertEqual(approval.ip, "203.0.113.7")
        XCTAssertEqual(approval.method, "POST")
        XCTAssertEqual(approval.statusCode, 200)
        XCTAssertTrue(approval.succeeded)
        XCTAssertEqual(approval.metadata?["decision"], .string("approve"))
        XCTAssertEqual(
            approval.createdAt,
            Date(timeIntervalSince1970: 1_784_548_800)
        )
    }

    /// Denied writes are recorded too — that is the point of the trail.
    func testDeniedEntryIsNotTreatedAsSuccess() throws {
        let page = try OperatorJSON.decoder.decode(AuditLogPage.self, from: Data(pageJSON.utf8))
        let denied = page.items[1]

        XCTAssertEqual(denied.actorType, .apiToken)
        XCTAssertEqual(denied.actorLabel, "token:booth-main")
        XCTAssertNil(denied.ip)
        XCTAssertNil(denied.metadata)
        XCTAssertFalse(denied.succeeded)
    }

    /// A successful sign-in is a redirect, so anything below 400 is a success.
    func testRedirectCountsAsSuccess() {
        let entry = AuditLogEntry(
            id: "a",
            action: "auth.login",
            actorType: .operatorUser,
            actorLabel: "operator@example.com",
            method: "GET",
            path: "/v1/auth/callback",
            statusCode: 302,
            createdAt: Date()
        )

        XCTAssertTrue(entry.succeeded)
    }

    func testActionTitleSplitsNamespaceAndCamelCase() {
        XCTAssertEqual(title(for: "message.approve"), "Message approve")
        XCTAssertEqual(title(for: "apiToken.revoke"), "Api token revoke")
        XCTAssertEqual(title(for: "transcription.push"), "Transcription push")
        XCTAssertEqual(title(for: "auth.login.denied"), "Auth login denied")
    }

    func testMetadataValuesRenderWithoutTrailingZeros() {
        XCTAssertEqual(AuditMetadataValue.number(184_320).displayString, "184320")
        XCTAssertEqual(AuditMetadataValue.bool(true).displayString, "yes")
        XCTAssertEqual(AuditMetadataValue.null.displayString, "—")
        XCTAssertEqual(
            AuditMetadataValue.array([.string("a"), .string("b")]).displayString,
            "a, b"
        )
    }

    /// Metadata is free-form JSON, so nested shapes must survive decoding.
    func testNestedMetadataDecodes() throws {
        let json = """
        { "counts": { "approved": 2 }, "tags": ["a", "b"], "dryRun": false }
        """
        let value = try OperatorJSON.decoder.decode(
            [String: AuditMetadataValue].self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(value["counts"], .object(["approved": .number(2)]))
        XCTAssertEqual(value["tags"], .array([.string("a"), .string("b")]))
        XCTAssertEqual(value["dryRun"], .bool(false))
    }

    /// The operator can add actor types without a client release, so one
    /// unknown value must not take the whole page down with it.
    func testUnknownActorTypeDecodesWithoutFailingThePage() throws {
        let json = #"""
        {
          "items": [
            {
              "id": "8f0a5f2e-2f3a-4c1c-9a2f-2a4f0b6d1e11",
              "action": "message.approve",
              "actorType": "serviceMesh",
              "actorLabel": "mesh",
              "method": "POST",
              "path": "/v1/messages/x/decision",
              "statusCode": 200,
              "createdAt": "2026-05-23T14:32:11Z"
            }
          ],
          "nextCursor": null
        }
        """#

        let page = try OperatorJSON.decoder.decode(
            AuditLogPage.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].actorType, .unknown("serviceMesh"))
        XCTAssertEqual(page.items[0].actorType.rawValue, "serviceMesh")
        XCTAssertEqual(page.items[0].actorType.label, "serviceMesh")
    }

    #if !os(watchOS) && !os(tvOS)
    /// The trail is admin-only, so a 403 needs to say so rather than look like
    /// a transient failure.
    func testForbiddenErrorExplainsAdminRequirement() {
        let message = AuditLogView.message(
            for: OperatorError.unauthorized(#"{"error":"forbidden"}"#),
            fallback: "Failed to load the audit log."
        )

        XCTAssertEqual(message, "The audit log is available to administrators only.")
    }

    /// The client collapses 401 and 403 into `.unauthorized`; an expired
    /// sign-in must not be reported as a privileges problem.
    func testExpiredSessionIsNotReportedAsAPermissionsProblem() {
        let message = AuditLogView.message(
            for: OperatorError.unauthorized(#"{"error":"unauthorized"}"#),
            fallback: "Failed to load the audit log."
        )

        XCTAssertEqual(message, "Your session has expired. Sign in again.")
    }

    /// A 5xx is the server falling over, not a refusal.
    func testServerFailureIsNotLabelledDenied() {
        let failed = AuditLogEntry(
            id: "a",
            action: "message.approve",
            actorType: .operatorUser,
            actorLabel: "operator@example.com",
            method: "POST",
            path: "/v1/messages/x/decision",
            statusCode: 503,
            createdAt: Date()
        )
        let denied = AuditLogEntry(
            id: "b",
            action: "message.approve",
            actorType: .anonymous,
            actorLabel: "anonymous",
            method: "POST",
            path: "/v1/messages/x/decision",
            statusCode: 403,
            createdAt: Date()
        )

        XCTAssertEqual(AuditLogRow.outcomeLabel(for: failed), "failed 503")
        XCTAssertEqual(AuditLogRow.outcomeLabel(for: denied), "denied 403")
    }

    func testActionFilterPrefixesExcludeSignOuts() {
        XCTAssertNil(AuditLogView.ActionFilter.all.prefix)
        XCTAssertEqual(AuditLogView.ActionFilter.messages.prefix, "message.")
        XCTAssertEqual(AuditLogView.ActionFilter.tokens.prefix, "apiToken.")
        XCTAssertEqual(AuditLogView.ActionFilter.signIn.prefix, "auth.login")
    }
    #endif

    private func title(for action: String) -> String {
        AuditLogEntry(
            id: "id",
            action: action,
            actorType: .system,
            actorLabel: "system",
            method: "POST",
            path: "/v1",
            statusCode: 200,
            createdAt: Date()
        ).actionTitle
    }
}
