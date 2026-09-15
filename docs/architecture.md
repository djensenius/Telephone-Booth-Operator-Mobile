# Architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│ Telephone-Booth-Operator-Mobile (Swift / SwiftUI, multi-platform) │
├──────────────────────────────────────────────────────────────────┤
│  App targets:                                                     │
│    • TBOperatorMobile           (iOS / iPadOS — universal)        │
│    • TBOperatorMobileMac        (macOS — native SwiftUI, sandbox) │
│    • TBOperatorMobileVision     (visionOS)                        │
│    • TBOperatorMobileTV         (tvOS — read-only dashboards)     │
│    • TBOperatorMobileWatch      (watchOS — standalone)            │
│    • TBOperatorMobileWidgets    (WidgetKit extension + Live Acts) │
│                                                                   │
│  Shared/                                                          │
│    Theme.swift             — Catppuccin Latte/Mocha               │
│    AuthManager.swift       — OIDC PKCE + Keychain (actor)         │
│    OperatorClient.swift    — typed REST + SSE + WS                │
│    Models/                 — Codable mirrors of openapi.yaml      │
│    LiveStatusStore.swift   — observable store fed by WS/SSE       │
│    Audio/                  — FLAC playback (AVAudioEngine)        │
│    Widgets/                — TimelineProvider + Live Activity     │
└──────────────────────────────────────────────────────────────────┘
                                  │  HTTPS bearer (Authentik JWT)
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│ Telephone-Booth-Operator (existing API)                           │
│   /v1/status, /v1/sessions, /v1/messages, /v1/questions,          │
│   /v1/instructions, /v1/events(/stream), /v1/system, /v1/ws/status │
│   + (added in operator PR 1) Authentik bearer middleware          │
│   + (added in operator PR 9) /v1/devices for APNs registration    │
└──────────────────────────────────────────────────────────────────┘
```

## Key decisions

### Installation lifecycle

`BoothStatus.installationState` is optional: `active` or
`between_exhibitions`. Only an explicit lifecycle value confirms downtime;
missing fields, empty data, HTTP 404, authentication failures, and network
errors never imply that an installation ended. The shared live store persists
the last explicit lifecycle per API base URL across app launches, including
on tvOS and watchOS, until an explicit active observation replaces it.

The signed-in apps poll REST every five seconds even with a healthy WebSocket,
so `/v1/status` (or the booth in `/v1/stats/summary` if status fails) reconciles
missed installation events across API replicas. WebSocket installation envelopes
also update lifecycle immediately; ordinary status frames cannot start or end
an installation. REST lifecycle ordering is independent of heartbeat timestamps.
An idless `isSynthetic: true` status with epoch `updatedAt` conveys lifecycle,
not a fresh heartbeat or a history entry.

Live polling keeps history and existing system snapshots cached; full refreshes
are reserved for seeding, manual refresh, and socket fallback. Switching API URLs
clears the previous server's data and Live Activities and restores only the new
URL's cached lifecycle, if any.
Widget snapshots and the coordinator cache are also cleared for every base-URL
change, including same-host path and port changes that do not require sign-out.

Shared dashboards use neutral **Between exhibitions / Offline expected**
presentation during confirmed downtime, retaining metrics and historical data.
An active synthetic status says **Waiting for booth**, not Idle, and never
displays an epoch timestamp. API connection and authentication errors remain
visible independently. Calls cannot start Live Activities during downtime;
existing activities end immediately. Widgets preserve the same lifecycle and
separately expose cache staleness.

Starting the next installation remains an explicit operator action in the web
console. Apple apps do not auto-start installations or retry a write as a start.
Scoped API writes rejected with HTTP 409 `application/problem+json`,
`error: installation_inactive`, remain errors through the existing client/UI
error handling. Pending booth recordings remain the booth client's
responsibility and are not discarded by these apps.

### Shared services

- Every write this app makes is recorded by the operator's audit trail with
  the operator, the IP and a timestamp; admins can read it back on the Audit
  tab. See [`audit-log.md`](audit-log.md).
- Mobile clients **never** talk to Postgres or Azure directly. Everything
  flows through the operator's versioned `/v1` API.
- Eligible iOS, iPadOS, macOS, and visionOS devices can enrich a message
  entirely on-device: download and verify its pre-signed audio, transcribe with
  SpeechAnalyzer, translate to English with Foundation Models, and generate an
  advisory moderation recommendation. The app then persists those results
  through the Operator API; it does not call the Transcription HTTP service.
  The moderation pass judges the speaker's meaning in context rather than
  isolated sensitive words. Concerning or initially declined results receive a
  second check that can approve clearly non-graphic, otherwise suitable context
  such as reports, metaphors, reflections, and requests for help. All other
  outcomes preserve the initial rejection or review, and unresolved model
  refusals become an unflagged "review" suggestion rather than a false positive.
- While an eligible app scene is active, its automatic processor claims one
  `/v1/message-processing` lease at a time and heartbeats it. Before moderation,
  it translates non-English transcripts to English and reviews English
  transcripts directly. Translation-only English claims complete with a
  pass-through result so the server can clear the requested step without
  invoking the translation model; the UI suppresses that redundant result. It
  releases work on backgrounding or when the device cannot support an
  installation's language, and treats lease loss or stale results as a
  release-and-reclaim refresh, so several devices can safely share the same
  installation queue without consuming retry attempts. Silent recordings are
  classified conservatively for human review; a delete recommendation never
  deletes a recording without the operator's confirmed action.
- Mobile clients authenticate with **OIDC Authorization Code + PKCE**
  directly against Authentik (no embedded webview, no cookie session).
- The operator API gains an additive bearer middleware (PR 1 in the
  operator repo) so the same `/v1` routes that accept the cookie session
  also accept Authentik JWTs.
- All app targets share `Shared/` (theme, auth, client, models). watchOS
  consumes only a slim subset (theme + auth + a few read endpoints) to
  keep binary size down.
- iOS, macOS, and visionOS widget extensions share one WidgetKit source
  catalog. Signed-in host apps write a versioned, privacy-bounded snapshot to
  the App Group; widget processes never authenticate or call the API.
- iOS / iPadOS / macOS / visionOS / tvOS 26.0 minimum, so we can use the
  full Liquid Glass design system natively.
