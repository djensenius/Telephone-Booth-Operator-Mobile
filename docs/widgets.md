# Widgets and Live Activities

> **Status:** scaffold. Concrete widgets arrive in PR 6, push integration in
> PR 10.

## Widget families

| Widget                         | Sizes              | Source endpoint                |
| ------------------------------ | ------------------ | ------------------------------ |
| `BoothStatusWidget`            | small / medium     | `GET /v1/stats/summary`        |
| `PendingModerationWidget`      | small / medium     | `GET /v1/stats/summary`        |
| `LatestMessageWidget`          | medium / large     | `GET /v1/messages?limit=1`     |

All widgets refresh on a 15-minute timeline; iOS may schedule fewer
updates under battery pressure. Tap-to-deep-link uses the
`tboperator://` URL scheme (`tboperator://moderation`, `tboperator://message/{id}`).

## Live Activity

`CallInProgressActivity` (iOS / iPadOS / watchOS) starts when a
`call.started` event arrives via APNs background push or via SSE while
the app is foregrounded. Updates flow through `ActivityKit` push tokens
issued in the operator (operator PR 9).

Lock-screen layout: caller icon, booth name, elapsed time.
Dynamic Island compact: phone glyph + elapsed time.
Dynamic Island expanded: same plus quick "approve" button.

## Platform availability

| Platform        | Widgets                                  | Live Activity              |
| --------------- | ---------------------------------------- | -------------------------- |
| iOS / iPadOS    | ✅ Home Screen + Lock Screen + StandBy   | ✅                         |
| macOS           | ✅ Notification Center + desktop         | ❌ (macOS has no LA)       |
| visionOS        | ✅                                       | ❌                         |
| watchOS         | ✅ as complications                      | ✅                         |
| tvOS            | ❌ (WidgetKit unsupported)               | ❌                         |
