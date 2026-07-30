//
//  OperatorClient+Audit.swift
//  TelephoneBoothOperatorMobile
//
//  The operator audit trail (`/v1/audit-logs`). Admin-only on the server.
//

import Foundation

extension OperatorClient {
    /// `GET /v1/audit-logs` — paged audit trail, newest first. Admin-only on
    /// the server; a non-admin operator gets `403`.
    ///
    /// `action` is matched as a prefix: `message.` is the whole family,
    /// `message.approve` just approvals, and `auth.login` also covers
    /// `auth.login.denied` and `auth.login.failed`.
    public func fetchAuditLogs(
        action: String? = nil,
        actorType: AuditActorType? = nil,
        cursor: String? = nil,
        limit: Int = 50
    ) async throws -> AuditLogPage {
        if await usesDemoData {
            // Prefix matching, the same rule the server applies.
            let items = DemoData.auditEntries.filter { entry in
                (action.map { entry.action.hasPrefix($0) } ?? true)
                    && (actorType.map { entry.actorType == $0 } ?? true)
            }
            return AuditLogPage(items: Array(items.prefix(limit)), nextCursor: nil)
        }
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        if let actorType {
            items.append(URLQueryItem(name: "actorType", value: actorType.rawValue))
        }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get("/v1/audit-logs", query: items)
    }

    /// `GET /v1/audit-logs/targets/{type}/{id}` — the trail for one thing.
    public func fetchAuditLogs(
        targetType: String,
        targetId: String,
        cursor: String? = nil,
        limit: Int = 50
    ) async throws -> AuditLogPage {
        if await usesDemoData {
            let items = DemoData.auditEntries.filter {
                $0.targetType == targetType && $0.targetId == targetId
            }
            return AuditLogPage(items: items, nextCursor: nil)
        }
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        // Interpolated raw: `AppConfig.url(forPath:)` percent-encodes each
        // path component, so pre-encoding here would double-escape it.
        return try await get("/v1/audit-logs/targets/\(targetType)/\(targetId)", query: items)
    }
}
