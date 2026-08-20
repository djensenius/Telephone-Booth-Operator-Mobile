# Widgets and Live Activities

The widget extensions render a compact snapshot written by a signed-in host
app to the shared App Group. Extensions never open the Keychain, refresh an
OIDC token, or call the Operator API.

## Widget catalog

| Widget | Primary families | Data |
| --- | --- | --- |
| `BoothStatusWidget` | accessory, small, medium | Booth state, runtime mode, update age |
| `PendingModerationWidget` | accessory, small, medium | Combined received + pending review queue |
| `CallsTodayWidget` | accessory, small, medium | Pickups today and currently in progress |
| `LatestMessageWidget` | small, medium, large | Message status and received time only |
| `SystemHealthWidget` | small, medium, large | Health severity, temperatures, memory, connectivity |
| `ActivitySummaryWidget` | medium, large | Rolling 24-hour pickup and message trend |
| `OperatorDashboardWidget` | large, extra large | Combined booth, queue, health, and latest-message metadata |

Accessory inline, circular, and rectangular layouts are offered only on
iOS/iPadOS. macOS and visionOS use the system-sized layouts supported by those
platforms.

## Snapshot and refresh flow

`WidgetRefreshCoordinator` serializes all writes to
`widget-snapshot.json`. The versioned payload contains independently dated
sections for:

- booth state and summary counts;
- latest-message metadata;
- system health;
- rolling 24-hour activity.

Live dashboard and pending-count updates merge only the sections they own.
Full refreshes fetch the summary, latest message, system telemetry, component
telemetry, and 24-hour overview without discarding a successful older section
when an unrelated endpoint fails.

Host apps request refreshes:

- after sign-in/session restoration and when becoming active;
- from booth WebSocket/poll updates while visible;
- after relevant remote notifications;
- through `BGAppRefreshTask` on iOS/iPadOS and visionOS;
- through `NSBackgroundActivityScheduler` on macOS.

Apple schedules background work at its discretion, so the requested
15-minute cadence is not a guarantee. Timelines reread the App Group snapshot
every 15 minutes and whenever the host asks WidgetKit to reload. Last-known
data remains visible with its age and a stale warning after 30 minutes.
Telemetry source data uses the dashboard's five-minute offline threshold.

Explicit sign-out, API-host changes, and demo-mode transitions clear the
snapshot.

## Privacy

Latest Message intentionally stores only its identifier, status, and
received/created time. Transcripts, translations, moderation reasons, notes,
audio metadata, tokens, and operator identity never enter the App Group
snapshot. Sensitive widget values opt into WidgetKit privacy redaction on
Lock Screen surfaces.

## Deep links

Widgets are read-only. Taps route through the `tboperator://` URL scheme to a
typed navigation store in the host app:

- `tboperator://dashboard`
- `tboperator://stats`
- `tboperator://sessions`
- `tboperator://sessions/{id}`
- `tboperator://messages?filter=review`
- `tboperator://messages/{id}`
- `tboperator://thermals`
- `tboperator://system`

If authentication is still restoring, the host retains one pending route and
consumes it after the signed-in shell is available.

## Live Activity

`CallInProgressLiveActivity` is iOS-only. It shows the booth, call state, and
elapsed time on the Lock Screen, Dynamic Island, and StandBy. Its action opens
the associated call/session in the app; moderation is never performed from
the Live Activity.

## Platform availability

| Platform | Widgets | Live Activity |
| --- | --- | --- |
| iOS / iPadOS | Home Screen, Lock Screen, StandBy | Yes |
| macOS | Desktop and Notification Center | No |
| visionOS | Spatial system-family widgets | No |
| watchOS | Not included in this widget pass | Existing watch app only |
| tvOS | Unsupported by WidgetKit | No |
