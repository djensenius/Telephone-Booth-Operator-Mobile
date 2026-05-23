# Privacy Policy

_Last updated: 2026-05-23_

Telephone-Booth-Operator-Mobile ("the app") is a front end for an
authenticated operator console. Privacy is not a goal — it's the bare
minimum. This document describes what the app does with data.

## Data the app collects

The app collects **no analytics**, **no advertising identifiers**, and
**no telemetry**.

## Data the app stores on-device

- **OIDC tokens** (access token, refresh token, ID token) issued by the
  Authentik instance configured by your operator deployment. Stored in the
  iOS / macOS Keychain. Deleted on sign-out.
- **Server URL** + non-secret settings, stored in `UserDefaults`.
- **SwiftData mirrors** of questions and draft moderation actions, used to
  let you edit while offline. Never leaves the device until you sync.
- **APNs device token** (if you enable push notifications), stored
  server-side via the operator's `/v1/devices` endpoint and locally for
  registration bookkeeping.

## Data the app sends off-device

- Authenticated API requests to **your** configured Telephone-Booth
  Operator instance. The app never contacts any other server.
- OIDC authentication requests to **your** configured Authentik instance.
- (Optional) APNs token registration to the operator instance, only if
  you opt in to push notifications.

The app does **not** send data to the developer.

## Audio and transcripts

Message audio (FLAC) and transcripts are fetched from the operator and
played back / displayed in the app. They are not cached to disk beyond
`URLCache`'s normal HTTP cache and are never uploaded anywhere.

## Children

Not directed at children under 13. Don't sign in to an operator console
as a child.

## Contact

Issues: <https://github.com/djensenius/Telephone-Booth-Operator-Mobile/issues>
