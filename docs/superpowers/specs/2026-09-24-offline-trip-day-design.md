# Phase 2B: the trip works offline, and a trip day has a Live Activity

Date: 2026-09-24. Status: approved in conversation; spec for review before planning.

## Why

Phase 1 fetches everything live. On a trip day the phone is often without
signal, and the app then shows the error card instead of the plan the
traveller already made. Phase 2A finished the search story (APNs, Universal
Links); 2B makes the trip itself usable on the road: the day's stops and saved
places readable offline, the forecast and money refreshed before the day, and
a Live Activity that keeps the current stop, the time left and the next stop
on the Lock Screen while the day unfolds.

Decisions taken with the owner:

- **Read-only cache.** Nothing is edited offline; edit controls disable with
  "Connect to edit". No queue, no merge logic; the editor's `baseVersion`
  stays the only concurrency story.
- **You start the activity, the schedule drives it.** No server scheduler,
  no push-to-start. A killed app keeps the countdown but advances only when
  the app next runs.
- **Serialized protos on disk**, not SwiftData. The cache is disposable and
  re-fetchable; `SearchStore` already does this for finished searches.
- **Not in 2B:** widgets (roadmap item 4, a slice on this model), offline
  edits, multi-city trips (2C: bookings, itineraries, hotels, restaurants,
  activities across several cities).

## What exists and is reused

| Piece | Where | Used for |
|---|---|---|
| `SearchStore` (proto bytes on disk, `.completeFileProtectionUntilFirstUserAuthentication`) | `Features/Search/Model/SearchEnvelope.swift` | the storage pattern |
| `BGAppRefreshTask` registration and scheduling | `SearchSessionController.swift:301-314` | a second task for trip prefetch |
| `CalendarSchedule` (09:00 start, 90 min, 15 min buffer, clamp 30–240) | `Features/Search/Model/DayGrouping.swift` | default stop timing |
| `POIProximityMonitor` (CLMonitor fences, 20 nearest, 60 m) | `Features/Nearby/Services/` | "arrived at the next stop" |
| `NearbyWalkAttributes`, `NearbyWalkWidgetBundle`, `Palette` | `NearbyWalkWidget/` | the Live Activity pattern and the widget target |
| `ResultsSideData` (local context + FX, cached per process) | `Features/Search/UI/Results/ResultsSideData.swift` | becomes cache-through |
| `TripDraft` / `TripDay` / `TripStop` | proto `loci/trip/trip.proto` | `TripDay.date`, `city_lat/lon`, `travel_day`; `TripStop.start_minute`, `duration_minutes`, `poi` (coordinates, hours); `TripDraft.legs` (`from_name`, `to_name`, `distance_km`) |
| RPCs already called | Trips: `listTrips`, `getTrip`; Saved: `getFavorites`, `getUserItineraries`, plus the two detail calls; side data: `getLocalContext`, `getFxRates` | the cache-through loaders |

## A. Data layer: `Core/Cache/LocalCache.swift`

```swift
actor LocalCache {
  enum Kind: String { case trip, trips, saved, localContext, fx }
  func put<M: SwiftProtobuf.Message>(_ message: M, kind: Kind, id: String) throws
  func get<M: SwiftProtobuf.Message>(_ type: M.Type, kind: Kind, id: String) -> Cached<M>?
  func ids(kind: Kind) -> [String]
  func remove(kind: Kind, id: String)
  func clear()   // on sign-out
}
struct Cached<M>: Sendable { let value: M; let fetchedAt: Date }
```

- Root: `Application Support/loci/cache/<kind>/<id>.bin`, written atomically
  with the same file protection as `SearchStore`; one `index.json` per kind
  holding `id → fetchedAt`. Ids: trip id; `"all"` for `trips` and `saved`;
  `"lat,lon"` rounded to 3 decimals for `localContext` and `fx`.
- `saved` is one message: a new local-only proto-free struct is avoided by
  storing the two responses under their own ids (`favorites`, `itineraries`)
  in the `saved` kind.
- `clear()` runs from `AuthService.logout()` beside `PushRegistration.unregister()`.

**Cache-through loading.** A small helper does the dance every loader needs:

```swift
func cached<M>(_ kind: LocalCache.Kind, id: String, fetch: () async throws -> M) async -> Loaded<M>
enum Loaded<M> { case fresh(M), stale(M, since: Date, error: APIError), missing(APIError) }
```

It returns the cached value first (callers render it, then await the fetch),
overwrites the cache on success, and on `APIError.network` returns `.stale`
with the cached copy. Any other error is `.missing` or, with a copy, still
`.stale` so an expired token does not blank the page. Loaders that adopt it:
Trips list, Trip editor (`getTrip`), Saved hub (both lists), `ResultsSideData`
(local context, FX). The detail sheets keep live-only behaviour.

**UI contract.** A page showing a cached copy carries one chip under its
title: "Saved 2h ago" while a refresh is in flight or succeeded, "Offline ·
last updated 2h ago" after a network error. The editor's edit controls
(reorder, rename, duration, add, replace, remove, pace) are disabled in the
stale state with the footer "Connect to edit". Nothing else changes visually.

## B. Refresh: `Core/Cache/TripPrefetch.swift`

- Task id `com.fernandocorreia.loci.trip-prefetch`, registered in
  `AppDelegate` beside the search reconcile task and added to
  `BGTaskSchedulerPermittedIdentifiers`.
- Scheduled whenever the cached trips contain a `TripDay` whose date is in the
  next 48 hours: earliest begin 22:00 the evening before that day, then every
  6 hours until 23:59 of the day. `TripPrefetch.nextBeginDate(trips:now:)` is
  pure and tested.
- Work: `getTrip` for that trip, `getLocalContext{days: 5}` and `getFxRates`
  for the day's `city_lat/lon` (falling back to the first stop with a
  coordinate), `getFavorites` + `getUserItineraries`. Each result goes through
  `LocalCache.put`. 25 s budget, then `setTaskCompleted(success:)`.
- Foreground: on `scenePhase == .active`, if today is a trip day and the
  cached local context for its city is older than 3 hours, refresh it.
- Best effort by design; the foreground path is the guarantee.

## C. Trip-day timeline: `Features/Trips/Model/DayTimeline.swift` (pure)

```swift
nonisolated struct TimelineSlot: Equatable, Sendable {
  let stop: Loci_Trip_TripStop; let index: Int
  let start: Date; let end: Date
  let coordinate: CLLocationCoordinate2D?
  let distanceToNextMeters: Double?
}
nonisolated enum DayTimeline {
  static func slots(day: Loci_Trip_TripDay, legs: [Loci_Trip_TripLeg], calendar: Calendar = .current) -> [TimelineSlot]
  static func today(in trip: Loci_Trip_TripDraft, now: Date, calendar: Calendar) -> Loci_Trip_TripDay?
  static func current(_ slots: [TimelineSlot], at: Date) -> TimelineSlot?   // the slot containing `at`, else the last one that ended
  static func next(_ slots: [TimelineSlot], after: TimelineSlot) -> TimelineSlot?
}
```

Timing rules, in order: a stop with `start_minute` starts then; otherwise it
starts when the previous slot ends plus `CalendarSchedule.bufferMinutes`; the
first stop without a start begins at `TripDay.day_start_minute` if set, else
`CalendarSchedule.dayStartHour` (09:00). Duration is `duration_minutes` when
set, else `CalendarSchedule.defaultMinutes` (90), clamped 30–240. Distance to
the next stop comes from the matching `TripLeg` (`from_name`/`to_name`) when
present, else the straight line between the two stops' `poi` coordinates,
else nil. `today` skips `travel_day` days and matches `date` in the phone's
calendar.

## D. Live Activity

**Shared attributes** (`nonisolated`, in the app target and the widget
target, like `NearbyWalkAttributes`):

```swift
nonisolated struct TripDayAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    enum Phase: String, Codable { case beforeFirst, atStop, between, done }
    var phase: Phase
    var currentIndex: Int
    var currentName: String
    var slotEnd: Date          // drives Text(timerInterval:)
    var nextName: String?
    var nextDistanceMeters: Double?
    var stopsDone: Int
  }
  let tripId: String; let dayId: String; let cityName: String; let stopCount: Int; let startedAt: Date
}
```

**Controller** (`Features/Trips/Services/TripDayActivityController.swift`,
`@Observable @MainActor`, one instance on `TripsView`/editor via the
environment):

- `start(trip:day:)` builds the slots, requests the activity
  (`@preconcurrency import ActivityKit`), fences the slots' coordinates with a
  `POIProximityMonitor`, schedules one local notification per slot end
  ("Time for <next stop>?", category `tripDay`, userInfo `{tripId, dayId,
  index}`), and stores `(tripId, dayId, startedAt)` in `UserDefaults` so a
  relaunch can re-adopt the activity (`Activity<TripDayAttributes>.activities`).
- `refresh(at:)` recomputes the state from the timeline and the manual
  offset: `manualIndex` overrides the schedule once the user taps Next or a
  fence fires, until the schedule catches up. Called on start, scene active,
  fence hit, notification tap, and after `advance()`.
- `advance()` moves to the next slot; `end()` ends the activity, removes the
  fences and pending notifications, clears `UserDefaults`.
- Auto-end: `refresh` ends the activity 30 minutes after the last slot's end,
  or 12 hours after `startedAt`. Starting for another day ends the running one.
- The Near me walk and a trip day can coexist (different attributes types).

**Widget** (`NearbyWalkWidget/TripDayLiveActivity.swift`, added to
`NearbyWalkWidgetBundle`; no new target, so no signing change):

- Lock Screen: header "Day in <city> · <done>/<count>", current stop name
  with `Text(timerInterval: now...slotEnd, countsDown: true)`, "Next: <name> ·
  <distance>" in terracotta, phase `done` shows "Day complete".
- Dynamic Island: compact leading `figure.walk`-style glyph
  (`mappin.and.ellipse`), compact trailing the countdown; expanded leading the
  current stop, trailing the countdown, bottom the next stop and distance.
- Colours from the existing `Palette`.

## E. UI

- **Trips list** (`TripsView`): a "Today" band above the list when a cached
  trip has a day today: city, first three stops, and "Start today" (or the
  running activity's current stop with "Open"). Reads the cache; never blocks
  on the network.
- **Trip editor** (`TripEditorView`): the cache chip under the title; on
  today's day header, Start / Next / Done controls bound to the controller;
  edit controls disabled in the stale state.
- **Saved hub** and **results side data**: the chip only.
- **Notification tap** on a slot-end reminder opens the editor on that day
  and calls `advance()`; `AppRouter` gains a `pendingTrip: (tripId, dayId)?`
  next to `pendingSession`.

## F. Errors and edge cases

- No trip day today: no band, no controls; the cache still serves.
- A day with zero stops or all stops without coordinates: activity runs on
  the schedule alone, no fences, distances nil.
- Time zone: the phone's calendar throughout; the server's `date` is a
  midnight timestamp, compared by calendar day.
- Location denied: fences skipped silently; schedule and Next still work.
- Live Activities disabled in Settings: `start` shows the existing
  `ActivityAuthorizationInfo` message pattern from the walk.
- Sign-out clears the cache and ends any activity.

## G. Tests (Swift Testing)

- `LocalCacheTests`: put/get round trip per kind, index `fetchedAt`, `ids`,
  `clear`; `cached(...)` returns `.stale` on `APIError.network` with a copy
  and `.missing` without.
- `DayTimelineTests`: defaults from 09:00, `start_minute` honoured, buffers,
  clamps, `day_start_minute`, `today` picks the calendar day and skips travel
  days, `current`/`next` at fixed instants, leg distance vs straight line.
- `TripDayActivityTests`: state for `beforeFirst`/`atStop`/`between`/`done`
  at fixed times; `advance` overrides then schedule catches up; auto-end
  after the last slot and after 12 hours; live-activity text shared with the
  widget (as `NearbyWalkTests` does).
- `TripPrefetchTests`: `nextBeginDate` for a day tomorrow, today, none in 48 h.

## H. Docs and preview

- `docs/ios/14-offline-trip-day.md`; `ROADMAP.md` items 2 and 3 marked done;
  `ARCHITECTURE.md` §13 and the study path updated.
- `-designPreview tripDay` renders the Today band and the editor's day header
  with a fixture trip (three stops in Rome); the Lock Screen view has a
  SwiftUI preview in the widget target.

## Order of work

1. `LocalCache` + `cached(...)` + tests. 2. Cache-through on Trips, editor,
Saved, side data, with the chip and the disabled edits. 3. `DayTimeline` +
tests. 4. `TripPrefetch` + registration + tests. 5. Attributes + widget view.
6. Controller + fences + reminders + tests. 7. Today band, editor controls,
router. 8. Preview, docs, TestFlight.
