# Audit log

The operator backend records write actions with the acting principal, the
client IP, the request path, the response status and a timestamp. This app
both **contributes** to that trail (its approvals, rejections and question
edits are writes) and **reads** it, on an admin-only Audit tab.

High-frequency booth telemetry — `PUT /v1/status`, `PUT /v1/system` and
`POST /v1/events` — is excluded by default and only recorded when the
operator sets `AUDIT_LOG_TELEMETRY=true`. Everything this app sends is
recorded either way.

The server-side design lives in
[`docs/audit-log.md`](https://github.com/djensenius/Telephone-Booth-Operator/blob/main/docs/audit-log.md)
in the operator repo; this page covers only the mobile side.

## The Audit tab

`Shared/Features/Audit/AuditLogView.swift`, shown on iOS, iPadOS, macOS and
visionOS. It is not built for watchOS or tvOS, which have no admin workflow.

Each row answers the three questions the trail exists for — who, from where,
and when — plus the outcome:

```text
Message approve                                        200
👤 operator@example.com
20 Jul 2026 at 12:00:00 · 203.0.113.7 · POST /v1/messages/…/decision
decision: approve · previousStatus: pending
```

A denied write is recorded too, and shows as `denied 403` in the warning
colour. That is deliberate: a rejected attempt is exactly the thing an audit
trail should keep.

The segmented picker filters by action family — All, Messages, Questions,
Tokens, Sign-in — by sending an `action` prefix the server matches. Sign-in
uses the `auth.login` prefix rather than `auth.`, so it does not also pull in
sign-outs. Paging is cursor-based: "Load more" follows `nextCursor`.

## Admin gating

The endpoint is admin-only server-side. `CurrentUserStore.isAdmin` (from
`/v1/auth/me`, fail-closed when absent) decides whether the tab is offered at
all, so a non-admin never taps into a guaranteed `403`. If a request is
rejected anyway — group membership changed mid-session, say — the view says
so in plain language instead of showing a raw server error.

## Client

`Shared/Networking/OperatorClient+Audit.swift`:

- `fetchAuditLogs(action:actorType:cursor:limit:)` →
  `GET /v1/audit-logs`
- `fetchAuditLogs(targetType:targetId:cursor:limit:)` →
  `GET /v1/audit-logs/targets/{type}/{id}`

Both return `AuditLogPage`. In demo mode they serve fixtures from
`DemoData.auditEntries`, filtered the same way the server would filter.

## Metadata

`AuditLogEntry.metadata` is free-form JSON — the operator deliberately keeps
it open-ended — so it decodes into `AuditMetadataValue`, a small recursive
enum covering strings, numbers, booleans, null, arrays and objects. It never
carries transcript text, plaintext tokens or SAS URLs, so it is safe to show
inline.

## What this app contributes

Every mutating call the app makes is attributed to the signed-in operator via
the Authentik bearer token, so approvals made from a phone are indistinguishable
in the trail from approvals made in the browser — except by `User-Agent`.
