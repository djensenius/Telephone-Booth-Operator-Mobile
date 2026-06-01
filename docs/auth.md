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

## Per-platform sign-in

Most targets (iOS, iPadOS, macOS, visionOS, watchOS) run the
`ASWebAuthenticationSession` PKCE flow above. Two platforms differ:

- **tvOS** uses the OAuth 2.0 Device Authorization Grant (RFC 8628) — no
  on-device browser. The TV shows a `user_code` plus a scannable QR code
  (`verification_uri_complete`) and polls `/token` until the user approves
  on a phone or computer. See `AuthManager+DeviceFlow.swift` and
  `TVDeviceLoginView.swift`.
- **watchOS** can reuse the paired iPhone's session via a phone-as-broker
  handoff (below), falling back to its own `ASWebAuthenticationSession`
  login when the phone is unreachable.

### watchOS phone-as-broker handoff

The standalone watch app avoids an on-watch browser login by borrowing the
paired iPhone's session over WatchConnectivity. Crucially, the **watch never
holds a refresh token**: Authentik rotates refresh tokens (each refresh
issues a new one and invalidates the old, with reuse detection), so two
devices refreshing the same lineage would invalidate each other and trigger
sign-out loops. Instead:

- The watch caches only a short-lived **access token + expiry**. A watch in
  "brokered mode" is identified by the *absence* of a refresh token in its
  Keychain (an on-watch OIDC fallback login would leave one).
- When the cached access token is missing or near expiry,
  `AuthManager.ensureValidToken()` / `validateSessionOnLaunch()` call
  `WatchAuthSync.ensureBrokeredToken()`, which `sendMessage`s the phone and
  awaits a reply. Transport is **pull-only** — the phone never pushes
  credentials, so a stale token can't arrive after the phone has rotated.
- The iPhone answers via `WCSessionDelegate.didReceiveMessage(...)`,
  calling `AuthManager.brokerAccessTokenForWatch()`. It refreshes its own
  session first if needed and returns `{ access_token, expiry, iss, cid }`.
  **The refresh token never leaves the phone.** The watch rejects a reply
  whose issuer/client id don't match its own `AppConfig`.
- Demo mode is excluded from brokering. If the phone is signed out it replies
  `{ tbo_ok: false, reason: "signed_out" }`, which signs the watch out too —
  this is how a phone-side sign-out propagates to the watch (on the watch's
  next token request).
- When the phone is unreachable and the cached access token has expired, the
  watch shows `LoginView` with a "Sign in with iPhone" button (retry the
  broker) and the on-watch OIDC login as a fallback.

The credential travels over the system-encrypted WatchConnectivity channel
between the paired devices, and is stored on the watch with the same
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` Keychain protection as
every other target. See `Shared/Auth/WatchAuthSync.swift` and
`Shared/Auth/AuthManager+WatchBroker.swift`.

> Note: 1Password (or any AutoFill credential provider) only fills the
> Authentik login form during an `ASWebAuthenticationSession`; it cannot
> share an OAuth session between devices. The broker handoff is the
> supported way to avoid a second login on the watch.

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
