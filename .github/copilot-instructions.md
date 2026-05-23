# Copilot instructions — Telephone-Booth-Operator-Mobile

These instructions tell GitHub Copilot (and any other AI assistant) how to work
inside this repository. Read them in full before proposing changes.

## Highest-priority rules

1. **Never add a `Co-authored-by: Copilot …` trailer to commits or PRs.** The
   project owner has explicitly opted out. Strip it from any default template
   before committing. Same rule for `Signed-off-by:` lines naming an AI.
2. **Don't mention AI assistance in commit messages, PR titles, PR bodies, or
   changelog entries.** No "generated with Copilot", "written by AI", etc.
3. **Don't commit secrets, real OAuth client secrets, real APNs keys, or
   anything from a real `.env`.** The Authentik client this app talks to is a
   **public** client (PKCE), so there is no client secret to leak — but never
   commit machine-generated `client_secret` values, p8 push keys, or signing
   identities.
4. **`swiftlint --strict` must pass before merging.** CI also runs an
   `xcodebuild` matrix across iOS, macOS, watchOS, visionOS, and tvOS, plus
   a `project.yml` ↔ `.xcodeproj` drift check. All must be green.
5. **NEVER run `xcodegen generate` locally.** The checked-in `.xcodeproj` is
   the source of truth. CI regenerates it from `project.yml` only to verify
   the two are in sync. Running xcodegen locally resets code signing,
   capabilities, entitlements, and other Xcode-managed settings. If
   `project.yml` needs changes, edit it manually and re-run xcodegen **only
   in a throwaway worktree** to inspect the diff, then mirror the relevant
   pbxproj changes by hand or accept the regeneration in one focused commit.

## What this repo is

A multi-platform Swift / SwiftUI front end for the **Telephone-Booth
Operator** ([`Telephone-Booth-Operator`][tbo]) — an art-installation operator
console for the 1980s Bell-Canada phone booth project ([`Telephone-Booth`][tb]
is the Rust phone client; [`Telephone-Booth-Transcription`][tbt] is the
macOS transcription proxy).

The mobile app **never** talks to Postgres or Azure directly. All state goes
through the operator's versioned `/v1` REST + SSE + WebSocket API. The app's
job is to make the operator console comfortable from an iPhone, iPad, Mac,
Apple Watch, Vision Pro, or Apple TV — including widgets and Live Activities
for at-a-glance booth health.

[tb]: https://github.com/djensenius/Telephone-Booth
[tbo]: https://github.com/djensenius/Telephone-Booth-Operator
[tbt]: https://github.com/djensenius/Telephone-Booth-Transcription

## Workspace layout

| Path | Contents |
| --- | --- |
| `project.yml` | xcodegen spec for all targets. Source of truth for build settings; the `.xcodeproj` mirrors this. |
| `TelephoneBoothOperatorMobile.xcodeproj` | Checked-in Xcode project. Generated from `project.yml`. |
| `Shared/` | Cross-target code: `Theme.swift`, `AuthManager.swift`, `OperatorClient.swift`, models. Pulled in by every app target. |
| `TBOperatorMobile/` | iOS / iPadOS universal target. |
| `TBOperatorMobileMac/` | macOS target (native SwiftUI, sandboxed). |
| `TBOperatorMobileWatch/` | watchOS standalone app + complications. |
| `TBOperatorMobileVision/` | visionOS target. |
| `TBOperatorMobileTV/` | tvOS read-only "booth wall" target. |
| `TBOperatorMobileWidgets/` | WidgetKit extension (Live Activity + widgets). |
| `TBOperatorMobile*Tests/` | XCTest / Swift Testing suites per platform. |
| `docs/` | Architecture, auth, widget design, runbooks. |
| `Icons/` | App icon source files (SVG + PSD). |
| `scripts/` | `make-icon.sh` and other helper scripts. |
| `.github/workflows/` | CI: `swiftlint.yml`, `build.yml` (matrix across all platforms with project drift check). |

## Tech stack & conventions

- **Language:** Swift 6 with strict concurrency. Use `Sendable` everywhere it
  fits. Prefer `actor` for shared mutable state (auth, networking, audio).
  Avoid `@unchecked Sendable` except where genuinely necessary.
- **UI:** SwiftUI everywhere. Embrace iOS / iPadOS / macOS / visionOS 26's
  Liquid Glass — `.glassEffect()`, `.glassBackgroundEffect()`, the new
  navigation chromes, and Liquid Glass widget rendering. tvOS uses focus
  engine + system materials (no Liquid Glass yet).
- **Theme:** Catppuccin Latte (light) / Mocha (dark) — see
  `Shared/Theme.swift`. Primary accent: soft-red maroon to echo the booth.
  Never use raw color literals — go through `Theme.Colors`.
- **Auth:** OIDC Authorization Code + PKCE via `ASWebAuthenticationSession`
  directly against Authentik. No embedded webview, no cookies. Tokens live
  in the Keychain. See `Shared/AuthManager.swift` and `docs/auth.md`.
- **Networking:** `URLSession` only. One shared `URLSession` per process.
  `OperatorClient` injects the bearer; tokens are auto-refreshed by
  `AuthManager`. Streaming endpoints use `URLSession.bytes(for:)` for SSE
  and `URLSessionWebSocketTask` for `/v1/ws/status`.
- **Models:** Codable Sendable structs mirroring the operator's
  `openapi.yaml`. When the operator updates its OpenAPI spec, regenerate
  via `swift-openapi-generator` (handled at build time by the SwiftPM
  plugin) and commit the deltas.
- **Persistence:** SwiftData for offline-edit-then-sync surfaces
  (questions, draft moderation actions). Read-only views use no on-disk
  cache beyond `URLCache`.
- **Logging:** `os.Logger` with subsystem `org.davidjensenius.TBOperatorMobile`.
  Categories per-feature. **Never log token contents or message audio.**

## Building, testing, linting

```bash
# Open the project in Xcode
open TelephoneBoothOperatorMobile.xcodeproj

# Lint (must pass strictly before commit; CI runs --strict)
swiftlint --strict --config .swiftlint.yml

# Build matrix (per platform; CODE_SIGNING_ALLOWED=NO for CI/simulator)
xcodebuild -project TelephoneBoothOperatorMobile.xcodeproj \
  -scheme TBOperatorMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Schemes: `TBOperatorMobile`, `TBOperatorMobileMac`, `TBOperatorMobileVision`,
`TBOperatorMobileTV`, `TBOperatorMobileWatch`, `TBOperatorMobileWidgets`.

**Initial builds take 10–20 minutes. Incremental builds 1–5 minutes. NEVER
CANCEL builds before 30 minutes — Swift compilation is slow.**

## PR workflow

1. Branch off `main`. Branch names: `feature/<short-slug>` or
   `fix/<short-slug>`.
2. Run `swiftlint --strict` and the relevant build before pushing.
3. Open the PR with a concise title and body that describes the change in
   user-visible terms. **Never** include "Co-authored-by: Copilot" or any
   AI-attribution language.
4. Wait for green CI on **all** matrix legs.
5. Address every Copilot review comment before merge. If a Copilot comment
   is wrong, push a follow-up commit that documents why with a one-line
   code comment or a short PR reply.
6. Squash-merge into `main`.

## Common patterns

### Auth state

```swift
@State private var auth = AuthManager.shared

switch auth.authState {
case .unknown:    ProgressView()
case .signedOut:  LoginView()
case .signedIn:   AuthenticatedRoot()
}
```

`AuthManager` is an `actor` exposing an `@Observable` snapshot. Never
call `URLSession` directly — go through `OperatorClient`, which calls
`await auth.ensureValidToken()` for every request.

### Theming

```swift
Text("Booth status")
    .font(Theme.Fonts.headerLarge())
    .foregroundStyle(Theme.Colors.textPrimary)
    .padding(Theme.Spacing.medium)
    .background(Theme.Colors.elevatedBackground)
    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
```

### Liquid Glass

On iOS / iPadOS / macOS / visionOS 26+, prefer `.glassEffect()` and
`.glassBackgroundEffect()` over raw materials for primary chrome. Fall
back to `.ultraThinMaterial` only when running on tvOS or in previews
where Liquid Glass isn't supported.

## Out-of-scope (do not add without an issue)

- Direct Postgres or Azure SDK calls (must go through operator API).
- API token management UI (security: web operator only).
- Localization beyond English (PR welcome but not required pre-1.0).
- TestFlight / App Store Connect automation (handled outside CI).
