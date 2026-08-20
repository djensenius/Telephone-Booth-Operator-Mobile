# Widgets and Live Activities

The widget extensions render a compact snapshot written by a signed-in host
app to the shared App Group. Extensions never open the Keychain, refresh an
OIDC token, or call the Operator API.

## Widget catalog

| Widget | Primary families | Data |
| --- | --- | --- |
| `BoothStatusWidget` | accessory, small, medium, large | Booth state; larger families add counts, health, and latest-message metadata |
| `PendingModerationWidget` | accessory, small, medium, large | Review queue; larger families add operational counts, booth, health, and latest-message metadata |
| `CallsTodayWidget` | accessory, small, medium, large | Pickups today; larger families add queue counts, booth, health, latest-message metadata, and activity |
| `LatestMessageWidget` | small, medium, large | Message status and received time only; larger families add counts, booth, health, and activity |
| `SystemHealthWidget` | small, medium, large | Health severity and telemetry; large adds booth, queue, latest-message metadata, and activity |
| `ActivitySummaryWidget` | medium, large | Rolling 24-hour pickup and message trend; large adds current booth, queue, and health context |
| `OperatorDashboardWidget` | medium, large, extra large | Combined booth, queue, health, latest-message metadata, and activity |

Accessory inline, circular, and rectangular layouts are offered only on
iOS/iPadOS. macOS and visionOS use the system-sized layouts supported by those
platforms.

## Adaptive layouts and previews

Layouts become progressively richer instead of simply scaling the compact
view. Small and accessory families keep one primary answer prominent. Medium
families use two columns to pair that answer with related counts or status.
Large families combine the primary widget with booth, queue, system,
latest-message, and 24-hour activity sections when those snapshot slices are
available. The dashboard uses the extra-large width for a two-column
operational overview. Supplemental sections retain their own freshness state:
if one endpoint is stale while the primary widget is current, that section
shows its own stale age instead of inheriting the primary section's status.

Every supported family has a named `#Preview` in its widget source file so it
can be reviewed in the Xcode canvas. The iOS-only preview catalog also covers
inline, circular, and rectangular Lock Screen widgets plus the Lock Screen,
expanded, compact, and minimal Live Activity presentations. Preview timelines
include populated data and, where useful, stale or unavailable states.

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
