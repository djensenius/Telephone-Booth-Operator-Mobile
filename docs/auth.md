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
| Scopes                      | `openid` `profile` `email` `offline_access`                         |
| PKCE                        | **Required**                                                         |
| Access code validity        | 60 seconds                                                           |
| Access token validity       | 5 minutes                                                            |
| Refresh token validity      | 30 days                                                              |

Bind the existing `telephone-booth-operators` group to the new
application's policy / group bindings (same group used by the web
operator).

The mobile app sends Authentik's access token to the operator API, so the
provider must include a `groups` claim in the access token. Authentik's
default `profile` scope mapping includes group membership. If your provider
has been customized and no longer emits `groups`, add a scope mapping on
`profile`:

```python
return {"groups": [group.name for group in user.groups.all()]}
```

That expression returns the signed-in user's group names. The operator API
then checks whether any returned group matches the configured allow-list
(`OIDC_ALLOWED_GROUPS` / `AUTHENTIK_ALLOWED_GROUPS`), usually
`telephone-booth-operators`.

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
   id_token, expires_in}`, validates the ID token claims locally (issuer,
   audience, expiration, nonce — see below), and stores the tokens in the
   Keychain.
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

## ID-token local validation

After token exchange, `AuthManager` validates the ID token's claims locally
via `IDTokenValidator`. This is a defense-in-depth measure — the backend
independently validates access tokens on every API call.

**What is validated:**
- `iss` — must match `oidcIssuerBase` from AppConfig (trailing-slash tolerant)
- `aud` — must contain our `oidcClientID`
- `exp` — must not have expired (5-minute clock skew tolerance)
- `nonce` — must match the nonce sent in the authorization request

**What is NOT validated (and why):**
- **JWT signature** — Per OIDC Core §3.1.3.7, when the ID token is received
  directly from the token endpoint over TLS (not via front-channel redirect),
  signature verification MAY be omitted. This avoids needing JWKS endpoint
  fetches, RSA/EC crypto, and key-rotation handling on-device. The TLS
  connection to the token endpoint provides integrity.

**Fail-open behavior:** If the provider returns no `id_token` in the token
response (valid per spec when `openid` scope is not granted or the provider
omits it), validation is skipped and a warning is logged. Sign-in proceeds
because the access token is still validated by the backend on every request.

## Staying signed in robustly

The session is designed to outlive the access-token lifetime (5 min) and
survive most transient failures. Three layers cooperate:

**1. Persistent storage.** Access + refresh + ID tokens live in the
Keychain under `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so they
survive app relaunches and OS reboots but are scoped to the device (no
iCloud-Keychain export, no restore to a new phone). See
`Shared/Auth/AuthManager+Keychain.swift`.

**2. Proactive refresh.** Tokens are refreshed automatically at three
checkpoints:

- **At launch** — `validateSessionOnLaunch()` runs from
  `RootContainerView.task` exactly once per process. If the cached access
  token is within 60 s of expiry (or already expired), it exchanges the
  refresh token before showing any UI. A 4xx from `/token` signs the user
  out cleanly; transient failures (no network, 5xx) keep the user signed
  in as long as the cached access token hasn't truly expired.
- **On foreground** — `RootContainerView` watches `scenePhase` and calls
  `ensureValidToken()` whenever the app becomes `.active`. This pre-warms
  the bearer after the device has been asleep so the first user-driven
  request doesn't pay the refresh latency.
- **Before every API call** — `OperatorClient` calls
  `auth.authorizationHeader()`, which goes through `ensureValidToken()`
  and refreshes if needed. Concurrent calls coalesce through
  `RefreshCoordinator` so we only ever issue one `/token` request at a
  time.

**3. Reactive retry.** Even with proactive refresh, an access token can
expire between our "is it expiring soon?" check and the actual HTTP
roundtrip (clock skew, slow uploads, server-side key rotation). To handle
this:

- `OperatorClient.send(...)` retries any 401 exactly once: it forces a
  refresh, swaps in the new bearer, and reissues the original request.
  Only after the retry also fails do we surface `OperatorError.unauthorized`.
- `EventStream` does the same at SSE connect time. Mid-stream 401s aren't
  possible (the HTTP connection is established once), but consumers
  should still reconnect with backoff on any stream end.

Together this means: a signed-in user who hasn't quit the app stays
signed in for the lifetime of the refresh token (30 days by default).
The Keychain still holds the refresh token across cold launches, so even
a force-quit + week-later relaunch typically resumes silently.

**When the user does get bounced to LoginView:**

- Refresh token expired (>30 days idle).
- Authentik admin revoked the session, deleted the user, or removed them
  from `OIDC_ALLOWED_GROUPS`.
- The operator API rotated its issuer / audience and the new server
  rejects every token we hold.

In all three cases `AuthManager.refreshTokenIfNeeded()` sees a 4xx from
`/token`, calls `signOut()`, and `RootContainerView` re-renders the login
screen on the next observation cycle.

## Open questions (to resolve during operator PR 1)

- Can Authentik issue tokens with both `aud=telephone-booth-operator`
  (web) and `aud=telephone-booth-operator-mobile` (mobile) accepted by
  the operator's middleware? Or do we accept a list of audiences?
- Does the operator's `/v1/events/stream` SSE endpoint accept
  `Authorization: Bearer …` headers, or does it need a query-param
  token fallback? (Some `EventSource`-style libraries can't set
  headers; Apple's `URLSession.bytes` can.)
