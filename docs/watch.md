# Apple Watch

The watch app provides four vertically paged screens: Status, Latest,
Moderation, and Stats. A single navigation stack opens message details from
Latest, the moderation queue, app links, and message notifications.

## Signing in

New watch sign-ins use the signed-in nearby iPhone. The watch does not offer
a new independent web sign-in. Its cached access token remains usable until
expiry; renewing a phone-brokered session requires the nearby iPhone. Refresh
tokens are not shared with the watch. Previously established independent watch
sessions remain valid. See [authentication](auth.md) for session details.

## Reviewing messages

Latest opens the full transcript, available English translation, applicable
moderation suggestion, and existing decision notes. Moderation shows up to
25 pending and 25 received messages, newest first. It is a bounded queue, not
the complete message archive; use iPhone for older messages and full filters.
If either status request fails, the watch retains the previous complete
snapshot and shows an error instead of silently hiding part of the queue.
Messages returned by both queries are deduplicated.

Pending messages can be approved or rejected. An approved or rejected message
can be changed to the opposite decision. Uploading, received, and unknown
statuses cannot be decided, matching the phone's status policy. Suggestions
are advisory and never automatically submit a decision.

Both actions require confirmation and use the operator API's existing
authenticated decision endpoint. Reject preserves the recording; it does not
delete it. Controls are disabled while loading or saving. Successful responses
update the detail, return to the originating page, and refresh that page and
the moderation count. Failed decisions remain visible and require reloading
server state before retrying; there is no optimistic success or offline queue.
The server remains responsible for authorization.

## Notifications and refresh

Only notification IDs belonging to loaded messages are cleared while their
page is active. Unfetched messages and aggregate queue alerts are not cleared
by a bounded list. Message links open the requested detail; review links open
Moderation. Links to unsupported screens explain that iPhone is required
instead of silently consuming the request.

Page refreshes run only while the watch scene is active and that page is
selected, with no detail or Settings covering it. Latest, Moderation, Stats,
and message details use the shared 30-second refresh cadence. Status polls
the authenticated HTTPS REST endpoints every five seconds, only while visible
and active. Opening Status does not start an additional one-shot refresh
alongside that service.

The watch never opens a live WebSocket. Apple restricts that low-level
networking API to specific watch use cases that do not include this operator
console; the simulator does not enforce that restriction. See
[Apple TN3135](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos).
Other platforms retain WebSocket updates with REST polling as a fallback.
Real-device sign-in and foreground refresh must be exercised before release;
simulator success alone does not establish watch networking compatibility.

Initial loading, successful empty results, and errors are distinct. Status
does not invent an idle state or zero counts before data arrives. Previously
loaded values remain visible during transient failures with an error banner.

## Intentionally unavailable on watch

Audio playback, transcript/translation editing, on-device transcription,
permanent deletion, editable decision notes, full message history and filters,
session details, thermals, full system diagnostics, question management, and
instruction management remain phone or larger-screen workflows. The watch
does not add alternative endpoints or bypass those screens' permissions.
