# Privacy Policy — Telephone Booth Operator

_Last updated: 2026_

Telephone Booth Operator ("the app") is a companion operator console for the
**Telephone-Booth** art installation. It is a private, single-operator tool
that connects to a self-hosted Telephone-Booth Operator server. This policy
explains what the app does and does not do with your information.

## Summary

- The app does **not** collect, sell, or share personal data with the
  developer or any third party.
- The app has **no analytics, advertising, or tracking SDKs**.
- All data the app displays comes from **your own** Telephone-Booth Operator
  server, reached over an encrypted connection that you configure.

## What the app stores on your device

- **Authentication tokens.** Sign-in uses OAuth 2.0 Authorization Code with
  PKCE against your Authentik identity provider. The resulting access and
  refresh tokens are stored in the iOS/macOS **Keychain** on your device and
  are used only to authenticate requests to your operator server. Tokens are
  never transmitted to the developer.
- **Local cache.** Read-only views may keep a short-lived in-memory or
  on-disk response cache (`URLCache`) and, for offline-edit surfaces, a local
  database on your device. This data never leaves your device except as
  requests to your own server.
- **Demo mode.** The app includes an offline demo mode backed by bundled
  sample data. Demo mode makes no network requests and stores nothing.

## What the app sends, and to whom

- The app communicates **only** with the Telephone-Booth Operator server and
  the Authentik identity provider that you configure. It does not contact any
  developer-operated servers.
- Requests carry your bearer token so the server can authorize them. The
  content of those requests and responses (booth status, call sessions,
  messages, statistics) is governed by your server's own privacy practices.

## Data the app does not collect

- No advertising identifiers.
- No location data.
- No contacts, photos, or microphone access for analytics.
- No usage analytics or crash-reporting telemetry sent to the developer.

## Children's privacy

The app is an operator tool for a private art installation and is not
directed to children.

## Changes to this policy

If this policy changes, the updated version will be published at this URL.

## Contact

Questions or requests can be filed as an issue at
<https://github.com/djensenius/Telephone-Booth-Operator-Mobile/issues>.
