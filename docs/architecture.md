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

- Mobile clients **never** talk to Postgres or Azure directly. Everything
  flows through the operator's versioned `/v1` API.
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
