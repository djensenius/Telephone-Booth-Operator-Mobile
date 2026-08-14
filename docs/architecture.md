# Architecture

> **Status:** scaffold. Concrete components arrive across PRs 2–11.

```text
┌──────────────────────────────────────────────────────────────────┐
│ Telephone-Booth-Operator-Mobile (Swift / SwiftUI, multi-platform) │
├──────────────────────────────────────────────────────────────────┤
│  App targets:                                                     │
│    • TBOperatorMobile           (iOS / iPadOS — universal)        │
│    • TBOperatorMobileMac        (macOS — native SwiftUI, sandbox) │
│    • TBOperatorMobileVision     (visionOS)                        │
│    • TBOperatorMobileTV         (tvOS — read-only booth wall)     │
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
│   /v1/events(/stream), /v1/system, /v1/ws/status                  │
│   + (added in operator PR 1) Authentik bearer middleware          │
│   + (added in operator PR 9) /v1/devices for APNs registration    │
└──────────────────────────────────────────────────────────────────┘
```

## Key decisions

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
  If the on-device model declines to classify a transcript, the app retries
  once with neutral wording and otherwise records an unflagged "review"
  suggestion with a reason, rather than a false positive.
- While an eligible app scene is active, its automatic processor claims one
  `/v1/message-processing` lease at a time, heartbeats it, and submits only
  the server-requested missing steps. It releases work on backgrounding or
  when the device cannot support an installation's language, and treats lease
  loss or stale results as a release-and-reclaim refresh, so several devices
  can safely share the same installation queue without consuming retry
  attempts. Silent recordings are classified conservatively for human review;
  a delete recommendation never deletes a recording without the operator's
  confirmed action.
- Mobile clients authenticate with **OIDC Authorization Code + PKCE**
  directly against Authentik (no embedded webview, no cookie session).
- The operator API gains an additive bearer middleware (PR 1 in the
  operator repo) so the same `/v1` routes that accept the cookie session
  also accept Authentik JWTs.
- All app targets share `Shared/` (theme, auth, client, models). watchOS
  consumes only a slim subset (theme + auth + a few read endpoints) to
  keep binary size down.
- iOS / iPadOS / macOS / visionOS / tvOS 26.0 minimum, so we can use the
  full Liquid Glass design system natively.
