# Telephone-Booth-Operator-Mobile

[![Build](https://github.com/djensenius/Telephone-Booth-Operator-Mobile/actions/workflows/build.yml/badge.svg)](https://github.com/djensenius/Telephone-Booth-Operator-Mobile/actions/workflows/build.yml)
[![Lint](https://github.com/djensenius/Telephone-Booth-Operator-Mobile/actions/workflows/swiftlint.yml/badge.svg)](https://github.com/djensenius/Telephone-Booth-Operator-Mobile/actions/workflows/swiftlint.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20iPadOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20visionOS%20%7C%20tvOS-lightgrey.svg)](#platforms)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg)](https://swift.org)

<p align="center">
  <img src="Icons/AppIcon-composite.png" alt="Telephone Booth Operator Mobile app icon" width="180" />
</p>

> _"This is Bell Canada calling. Please hold for the operator."_

A native Swift / SwiftUI front end for the
[Telephone-Booth-Operator](https://github.com/djensenius/Telephone-Booth-Operator)
console — the operator UI for the Telephone-Booth art installation, a
soft-red glass-and-aluminum 1980s Bell Canada booth with a Northern Electric
Contempra rotary phone inside. The web operator approves calls; this app
approves them from your wrist, your pocket, your couch, or your headset.

The mobile app **never** talks to Postgres or Azure directly. All state
flows through the operator's versioned `/v1` REST + SSE + WebSocket API. The
operator gains a small Authentik bearer-token middleware so this app — and
any future mobile client — can sign in with PKCE and call the same endpoints
the browser cookie session uses today.

```text
   ╔═══════════════════════╗
   ║   📞  T E L E P H O N E ║
   ╠═══════════════════════╣
   ║                       ║
   ║     ┌─────────┐       ║
   ║     │  ◐ ◐ ◐  │       ║   ← live status lamps
   ║     │ ─────── │       ║
   ║     │ ╭─────╮ │       ║
   ║     │ │  ⊙  │ │       ║   ← Contempra phone (rotary nav)
   ║     │ ╰─────╯ │       ║
   ║     └─────────┘       ║
   ║                       ║
   ║   [COIN RETURN]       ║
   ╚═══════════════════════╝
```

## Platforms

| Platform   | Deployment | Form factor                                                  |
| ---------- | ---------- | ------------------------------------------------------------ |
| iOS        | 26.0       | iPhone + iPad universal target with Liquid Glass chrome      |
| macOS      | 26.0       | Native SwiftUI, sandboxed                                    |
| watchOS    | 26.0       | Standalone companion + complications                         |
| visionOS   | 26.0       | Spatial operator dashboard                                   |
| tvOS       | 26.0       | Read-only "booth wall" for installation displays             |

Widgets and a `CallInProgress` Live Activity ship on every platform that
supports WidgetKit (iOS, iPadOS, macOS, visionOS, watchOS).

## Building and testing

This project uses [xcodegen](https://github.com/yonaskolb/XcodeGen). The
checked-in `.xcodeproj` is the source of truth; **never run `xcodegen
generate` locally**. CI regenerates from `project.yml` only to verify the
two are in sync.

```bash
# Open the project
open TelephoneBoothOperatorMobile.xcodeproj

# Lint (strict — CI enforces this)
swiftlint --strict --config .swiftlint.yml

# Build per platform (CODE_SIGNING_ALLOWED=NO for simulator / CI)
xcodebuild -project TelephoneBoothOperatorMobile.xcodeproj \
  -scheme TBOperatorMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Available schemes: `TBOperatorMobile` (iOS / iPadOS), `TBOperatorMobileMac`,
`TBOperatorMobileVision`, `TBOperatorMobileTV`, `TBOperatorMobileWatch`,
`TBOperatorMobileWidgets`.

## Authentication

OIDC Authorization Code + PKCE via `ASWebAuthenticationSession`, talking
directly to Authentik. No client secret (public client), no embedded
webview, no cookie session. Refresh tokens live in the Keychain. See
[`docs/auth.md`](docs/auth.md) for the full flow.

## Documentation

| Doc                                          | When you need it                          |
| -------------------------------------------- | ----------------------------------------- |
| [`docs/architecture.md`](docs/architecture.md) | How the pieces fit together              |
| [`docs/auth.md`](docs/auth.md)               | OIDC PKCE flow + Authentik native client  |
| [`docs/widgets.md`](docs/widgets.md)         | Widgets + Live Activity design            |

## License

Apache-2.0 — same as the original
[`Telephone-Booth`](https://github.com/djensenius/Telephone-Booth) and
[`Telephone-Booth-Operator`](https://github.com/djensenius/Telephone-Booth-Operator)
projects.
