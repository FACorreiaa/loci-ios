# iOS: search keeps running, notifies, and reopens

**Goal:** start an itinerary, hotels, restaurants or activities search, leave the screen or the app, get told when it finishes, and tap back into that exact session.

**Status:** Phase 1 uses local notifications only. The server has no device-token RPC and no APNs sender; loci-3a owns that, and the contract is not approved yet. The payload below already uses the keys loci-3a plans for its push, so APNs can plug into the same router later.

## Session model (same as web)
- **A search is one `ChatService.StreamChat` call.** The server picks the domain and says so in the first event: `StartPayload{session_id, domain, city_name}`.
- **Route from the domain**, exactly like web's `getDomainRoute`:
  - `general` and `itinerary` → `itinerary`
  - `accommodation` → `hotels`
  - `dining` → `restaurants`
  - `activities` → `activities`
- **Deep link:** `loci://<route>?sessionId=…&cityName=…&domain=…`. This is the web URL `/<route>?sessionId=&cityName=&domain=` with `loci` as the scheme.
- **One active search at a time.** Starting another asks before replacing it. Stop cancels the client stream; the server may still finish, but nothing is notified.

## Payload
The keys are shared by the deep link, the local notification and the planned server push (`SessionLink.Key`):

```json
{ "sessionId": "8c1…", "cityName": "Lisbon", "domain": "itinerary" }
```

- The notification id is `search-<sessionId>`, so a later post for the same search replaces the earlier one.
- The title depends on the result, e.g. "Your itinerary for Lisbon is ready", "Hotels for Porto are ready", "Your search for Rome didn't finish".

## Lifecycle
```
start ── StreamChat ──▶ events ──▶ SearchState (tokens append live)
  │                        │
  │                        └─ after every event: envelope → Application Support
  │                             {sessionId, requestId, profileId, lastEventId, query, city, domain, lat/lon}
  │
  ├─ COMPLETE / ERROR ─▶ save the result on the phone ─▶ notify unless the user is looking at it
  │
  ├─ app goes to background ─▶ beginBackgroundTask: keep reading
  │      └─ time runs out ─▶ cancel the client stream (the server keeps generating),
  │                          keep the envelope, schedule BGAppRefresh "…search-reconcile"
  │
  ├─ BGAppRefresh ─▶ GetChatSession once ─▶ finished? notify : reschedule (give up after 5 min + margin)
  │
  └─ app active again ─▶ StreamChat{sessionId, resumeToken: lastEventId}
         └─ ends without COMPLETE ─▶ poll GetChatSession, 2s → 30s backoff, up to about 5 min
```

"Finished" when polling means `session.currentItinerary` is present and `session.updatedAt` is later than this search's start. The time check matters because a follow-up reuses a session that already has a result.

## Routing a tap
1. `UNUserNotificationCenterDelegate.didReceive` → `SessionLink(userInfo:)` → `AppRouter.open(link)`.
2. That selects the Ask Loci tab and pushes `SearchResultsView(link)`.
3. The page restores in web's `restoreOrHydrateSession` order:
   1. the live search, if it is this session
   2. this phone's saved copy (`result-<sessionId>.bin`)
   3. `GetChatSession.currentItinerary`
   4. a "Run the search again" button

`loci://…` URLs from `onOpenURL` take the same path. `loci://oauth2redirect/*` is left for sign-in.

## When the app is in the foreground
- If the user is on that result page, nothing is posted; the page is already showing it.
- Anywhere else in the app, the notification shows as a banner (`willPresent` returns `.banner`). Tapping it routes as above.

## Failure cases
| Case | What happens |
|---|---|
| Notification permission denied | Nothing is posted. The result is still on the Ask Loci tab ("Running now" / Recent), and the page restores. |
| App killed mid-search | The envelope survives. The next BGAppRefresh, or the next launch, reconciles through GetChatSession. Known gap until APNs: iOS decides when BGAppRefresh runs, so the alert can come late, or only when the app is next opened. |
| Resume buffer gone (evicted after 15 min idle, pod restart, a different pod) | The replay comes back empty, then GetChatSession polling takes over. If the server finds nothing to replay it starts a new generation for that session (server behaviour, same as web). |
| Resume before generation ends | The server replays what is buffered and then closes; it does not follow the live generation (bug, owned by loci-3a). iOS treats "ended without COMPLETE" as "still working" and polls. |
| Several events share one `event_id` (server bug) | Deduplication uses `(event_id, payload case)`, so no real event is dropped. |
| No `lastEventId` yet | iOS does not call StreamChat to resume, because without a resume token the server would run the search again and spend quota. It polls GetChatSession instead. |
| No session id yet (killed before `start`) | Nothing on the server to find. The search is marked interrupted and offers a re-run. |
| Hotels, restaurants or activities finished while detached | The proto `AiCityResponse` has no fields for those lists, so the server can confirm completion but not return them (web skips this step too). The notification still fires. The page shows the phone's copy if it has one, otherwise "didn't reach this phone" with a re-run. |
| Quota (`ResourceExhausted` + `x-loci-quota-reason`) | The search fails with web's message ("today's 10 free searches…" / "fair-use limit…"). No paywall. |
| Token expired | Refreshed before the stream opens. An Unauthenticated error before the first event refreshes once and reopens. A rejected refresh signs the user out. |
| Network drop mid-stream | Treated as detached, not failed. The app polls GetChatSession. |
| No travel profile | The search doesn't start. A sheet opens Travel profiles (web's DeskHero throws the same). |

## Moving to APNs (Phase 2)
- Register the device token through loci-3a's RPC once it is approved (platform `APNS`).
- The server sends `{sessionId, cityName, domain}` plus a title and body. `SessionLink(userInfo:)` already parses that, so the tap routing does not change.
- The local notification stays as the foreground and fast path. Deduplicate on the `search-<sessionId>` id.
