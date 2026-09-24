# Slice 14: the trip works offline, and a trip day has a Live Activity (Phase 2B)

Spec: `../superpowers/specs/2026-09-24-offline-trip-day-design.md`. Plan:
`../superpowers/plans/2026-09-24-offline-trip-day.md`.

Phase 1 fetched everything live, so a trip day without signal showed the error
card instead of the plan. Now trips, saved places, the forecast and money stay
readable from the phone's copy, the next trip day is refreshed in the
background, and a trip day can run as a Live Activity driven by its schedule.

| Piece | Where | What it does |
|---|---|---|
| `LocalCache` | `Core/Cache/LocalCache.swift` | Serialized protos on disk (`Application Support/loci/cache/<kind>/<id>.bin`) with a per-kind `index.json` of fetch times. Kinds: `trip`, `trips`, `saved`, `localContext`, `fx`. Cleared on sign-out. |
| `cacheThrough` / `Loaded` | `Core/Cache/Loaded.swift` | Render the copy (`onCached`), fetch, overwrite. `.fresh`, `.stale(copy, since, reason)` or `.missing`. Only `APIError.network` reads as offline; any other failure with a copy still shows the copy. |
| `CacheChip` | `Core/Cache/CacheChip.swift` | "Saved 2 hours ago" / "Offline · last updated 2 hours ago" under a page drawing its copy. |
| `TripPrefetch` | `Core/Cache/TripPrefetch.swift` | `BGAppRefreshTask` `com.fernandocorreia.loci.trip-prefetch`: 22:00 the evening before the next trip day, then every six hours on the day. Refreshes that trip, `GetLocalContext{days: 5}` and `GetFxRates` for the day's city. On app open, refreshes today's forecast when the copy is older than three hours. |
| `DayTimeline` | `Features/Trips/Model/DayTimeline.swift` | A `TripDay` as `[TimelineSlot]`: `start_minute` wins, else the previous slot plus 15 min; `duration_minutes` else 90, clamped 30–240; the trip's `constraints.day_start_minute` else 09:00. Distance to the next stop from the matching `TripLeg`, else the straight line. `today(in:)` reads the server's midnight-UTC date as a calendar day. |
| `TripDayAttributes` | `Shared/TripDayAttributes.swift` (app and widget targets) | The activity's content: phase (`beforeFirst`, `atStop`, `between`, `done`), current stop, `slotEnd` for the countdown, next stop and distance, stops done. |
| `TripDayLiveActivity` | `NearbyWalkWidget/TripDayLiveActivity.swift` | Lock Screen and Dynamic Island views, in the existing extension. |
| `TripDayActivityController` | `Features/Trips/Services/TripDayActivityController.swift` | Start / advance / end / refresh. The schedule decides the current stop; Next, a reminder tap or a geofence hit (its own `CLMonitor`, `loci-trip-day`) move ahead of it until the schedule catches up. One reminder per slot end ("Time for Pantheon?"). Ends 30 min after the last slot or 12 h after start. Re-adopts a running activity after a relaunch. |
| `TodayBand`, `TodayControls` | `Features/Trips/UI/TodayBand.swift` | The band above the trips list on a trip day, and Start / Next / Done in the editor's day header. |

## Cache-through pages

Trips list, trip editor, Saved hub (favourites and itineraries) and the result
page's forecast strip. Each renders the copy immediately, then fetches. The
editor disables every edit (reorder, rename, duration, pace, add, replace,
remove) while it is drawing a copy the server has not confirmed, with the
footer "Connect to edit". Nothing is queued: option 1 of the spec, read-only.

## Trip day rules

- The server stores a day as midnight UTC of a calendar date. `DayTimeline.
  localMidnight` reads the date back in UTC and places it at midnight in the
  phone's calendar, so a traveller west of UTC does not see the day a day
  early. Travel days are skipped; two days on the same date give the first.
- A reminder tap advances the activity and opens the editor on that trip
  (`AppRouter.pendingTrip`, consumed by the Calendar tab's stack).
- Live Activities off in Settings: the Start button is disabled with a hint.
  Location denied: no fences, Next and the schedule still work.

## Known gap: stop coordinates

The server's trip mapper does not fill `TripStop.poi` today, so real trips
arrive with no coordinates: the geofences and the "Next · 1.2 km" distance
only run on fixtures and the design preview, and a real day advances by the
schedule, Next and the reminders alone. Hydrating the POI in `tripToProto`
(loci-connect-server `internal/domain/trip/mappers.go`) turns both on with no
app change.

## Checking it

Unit: `LocalCacheTests`, `CacheThroughTests`, `DayTimelineTests`,
`TripPrefetchTests`, `TripDayActivityTests`.

Device: open Trips online, turn on airplane mode, reopen: the list and a trip
render with "Offline · last updated …" and edits are disabled. On a trip day,
Start today puts the activity on the Lock Screen; Next moves it; lock the
phone and watch the countdown; Done ends it. `-designPreview tripDay` renders
the Today band offline.
