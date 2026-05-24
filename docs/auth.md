# Authentication

The mobile app uses **OIDC Authorization Code + PKCE** directly against
Authentik. This document describes how to register the app on Authentik
and how the in-app flow works once the bearer middleware lands in the
operator API (operator PR 1).

> **Status:** implemented in PR 2. `Shared/Auth/AuthManager.swift` is the
> entrypoint; tokens persist in the Keychain and refresh proactively when
> they're within 60 s of expiry.

## Authentik: register the mobile client

> _Authentik admin UI → Applications → Providers → Create → OAuth2/OpenID
> Provider_

| Field                       | Value                                                                |
| --------------------------- | -------------------------------------------------------------------- |
| Name                        | `telephone-booth-operator-mobile`                                    |
| Authorization flow          | `default-authorization-flow (Authorize Application)`                 |
| Client type                 | **Public** (no client secret — required for PKCE on mobile)          |
| Client ID                   | _auto-generated; copy it into `OIDCClientID` in `project.yml`_       |
| Redirect URIs               | `tboperator://oauth/callback`                                        |
| Signing Key                 | _default (RSA)_                                                      |
| Subject mode                | Based on the User's hashed ID                                        |
| Include claims in id_token  | Yes                                                                  |
| Scopes                      | `openid` `profile` `email` `offline_access` `goauthentik.io/api`     |
| PKCE                        | **Required**                                                         |
| Access code validity        | 60 seconds                                                           |
| Access token validity       | 5 minutes                                                            |
| Refresh token validity      | 30 days                                                              |

Bind the existing `telephone-booth-operators` group to the new
application's policy / group bindings (same group used by the web
operator).

## In-app flow

1. User taps **Sign in** in `LoginView`.
2. `AuthManager` generates `state`, `nonce`, and a 43-byte `code_verifier`,
   derives the `code_challenge` (S256), and stores them in memory.
3. `AuthManager` opens an `ASWebAuthenticationSession` pointed at
   `${AUTHENTIK_ISSUER}/authorize?...`. The system browser shows
   Authentik's login.
4. After consent, Authentik redirects to `tboperator://oauth/callback?code=…&state=…`,
   which `ASWebAuthenticationSession` captures and returns to the app.
5. `AuthManager` POSTs the code + verifier to
   `${AUTHENTIK_ISSUER}/token`, receives `{access_token, refresh_token,
   id_token, expires_in}`, validates the ID token signature against the
   Authentik JWKS, and stores the tokens in the Keychain.
6. `OperatorClient` injects `Authorization: Bearer <access_token>` on
   every request. Five minutes later, the access token expires;
   `AuthManager` exchanges the refresh token for a new pair before the
   next call.
7. Sign-out clears the Keychain, optionally calls the Authentik
   `/end-session` endpoint, and resets `AuthManager.authState` to
   `.signedOut`.

## Why not the operator's cookie session?

- ASWebAuthenticationSession on Apple platforms gives the user a real
  Safari-backed login (1Password / passkey support, no embedded webview
  warning).
- The refresh-token gating can be backed by `LAContext` / passkey, so the
  app can require biometric to unlock long-lived sessions without
  needing a network round-trip.
- The operator's cookie was designed for the browser — server-side
  state, CSRF middleware, `__Host-` prefix rules — none of which map
  cleanly to a native client.

## Open questions (to resolve during operator PR 1)

- Can Authentik issue tokens with both `aud=telephone-booth-operator`
  (web) and `aud=telephone-booth-operator-mobile` (mobile) accepted by
  the operator's middleware? Or do we accept a list of audiences?
- Does the operator's `/v1/events/stream` SSE endpoint accept
  `Authorization: Bearer …` headers, or does it need a query-param
  token fallback? (Some `EventSource`-style libraries can't set
  headers; Apple's `URLSession.bytes` can.)
