//
//  DemoData+Audit.swift
//  TelephoneBoothOperatorMobile
//
//  Sample audit entries for previews and App Review demo mode.
//

import Foundation

extension DemoData {
    public static let auditEntries: [AuditLogEntry] = [
        AuditLogEntry(
            id: "demo-audit-3",
            action: "message.approve",
            targetType: "message",
            targetId: "demo-message-1",
            actorType: .operatorUser,
            actorUserId: "demo-operator",
            actorLabel: "operator@example.com",
            ip: "203.0.113.7",
            userAgent: "TBOperatorMobile/demo",
            method: "POST",
            path: "/v1/messages/demo-message-1/decision",
            statusCode: 200,
            metadata: ["decision": .string("approve"), "previousStatus": .string("pending")],
            createdAt: now.addingTimeInterval(-4 * 60)
        ),
        AuditLogEntry(
            id: "demo-audit-2",
            action: "message.complete",
            targetType: "message",
            targetId: "demo-message-2",
            actorType: .apiToken,
            actorTokenId: "demo-token",
            actorLabel: "token:booth-main",
            ip: "198.51.100.24",
            userAgent: "telephone-booth/0.8.4",
            method: "POST",
            path: "/v1/messages/demo-message-2/complete",
            statusCode: 200,
            metadata: ["sizeBytes": .number(184_320)],
            createdAt: now.addingTimeInterval(-38 * 60)
        ),
        AuditLogEntry(
            id: "demo-audit-1",
            action: "apiToken.revoke",
            targetType: "apiToken",
            targetId: "demo-token-old",
            actorType: .operatorUser,
            actorUserId: "demo-operator",
            actorLabel: "operator@example.com",
            ip: "203.0.113.7",
            userAgent: "TBOperatorMobile/demo",
            method: "DELETE",
            path: "/v1/api-tokens/demo-token-old",
            statusCode: 403,
            metadata: ["reason": .string("not_admin")],
            createdAt: now.addingTimeInterval(-3 * 60 * 60)
        )
    ]
}
