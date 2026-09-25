# Walk a day: GPS-style navigation stop by stop (iOS)

Status: design approved in chat 2026-09-25; this spec is the written version for review.

## Why
Near me directions (slice 20) work on a phone as of TestFlight 1.0 (39): tap a place, press Go, and a walker figure follows a walking route to it. The user wants the same experience for a whole day of a plan, walking from one stop to the next.

## What the user decided
- **Two sources.** Trip days (Trips / Calendar → trip editor) and saved itineraries (Saved → Itineraries). They ship as two PRs: A covers the walk and trip days, B covers saved itineraries.
- **Arrival pauses.** Reaching a stop buzzes and shows "You're at X (2 of 6)". The route to the next stop starts only when the person taps **Walk to next**. There is no automatic re-routing while they are visiting.
- **Any day can be walked**, dated or not, today or not.
- **Trip-day mode runs side by side.** It is the existing "Start today" mode, with its schedule, reminders and Lock Screen card, and a walk does not change it. If both are running, the Lock Screen shows two cards.

## What exists and is reused
| Piece | Where | Reuse |
|---|---|---|
| Route to one place, rerouting, arrival | `Features/Nearby/Services/WalkNavigator.swift` | As is. Its destination is a `Loci_Poi_POIDetailedInfo`, and trip stops carry one in `TripStop.poi`. |
| Route geometry | `Core/Navigation/WalkingRoute.swift` | As is. |
| Steps | `Core/Motion/WalkTracker.swift` | As is. |
| Walker figure, route line, follow camera | `NearbyView.swift`, `WalkerFigure.swift` | Pulled out into a shared map layer (see Components). |
| Lock Screen walk card | `Shared/NearbyWalkAttributes.swift`, `NearbyWalkWidget/NearbyWalkLiveActivity.swift` | Extended with optional fields. |
| Trip stops with coordinates | `Loci_Trip_TripDay.stops[].poi`, `DayTimeline.coordinate(of:)` | Source for A. |
| Saved itinerary → its search result | `SearchSessionController.state(for: SessionLink)` then `SearchState.dayGroups` | Source for B. |

## Behaviour
1. **Start.** "Walk this day" opens `WalkDayView` for that day's stops, in plan order. Stops without a usable coordinate (no `poi`, or 0,0) are left out, and the screen says "2 stops have no location and are skipped". With no routable stops the button is disabled. Starting previews the route from the current location to stop 1 and begins following it at once: the camera follows the walker and the Lock Screen card appears.
2. **Walking to stop N.** This is the Near me behaviour: a solid line that trims as the person walks, a new route after 2 fixes more than 40 m off (at most one every 10 s), the walker figure, a follow camera, and **Recenter** after a pan. The card reads "→ 3 of 6 · Café X · 400 m · 5 min · 1,240 steps", with **End**.
3. **Arrival** (within 25 m). The phone gives a success haptic, and a local notification "You're at X (3 of 6)" is posted if the app is not active. The solid line clears and a dashed preview to the next stop appears (as in Near me preview). The card reads "You're at X (3 of 6)" and offers **Walk to next: Y · 8 min**, which is a preview route fetched on arrival, plus **Skip**. The step count keeps running.
4. **Walk to next** follows the previewed route to stop N+1. **Skip** marks N+1 skipped and moves to N+2 in the same arrived state, with a new preview.
5. **Jump.** A stop list (sheet) shows each stop as done, skipped, next or upcoming. Tapping one routes to it and follows at once.
6. **Done.** After the last stop, the card shows a summary: "Day walked · 6 stops (1 skipped) · 5.2 km · 7,900 steps", with **Done**, which ends the walk.
7. **End** at any time stops the location loop, the pedometer and the Lock Screen card.
8. **One walker at a time.** Starting a day walk stops a running Near me walk, and starting a Near me walk stops a day walk. This keeps one location loop and one walk card. Trip-day mode is untouched.
9. **Locked phone.** The `location` background mode, which is already on, keeps the walk's `liveUpdates` loop running, so arrival is detected and notified while the phone is locked.

## Components
### `Features/Walk/Model/WalkStop.swift`
`struct WalkStop: Equatable, Identifiable { id: String; name: String; poi: Loci_Poi_POIDetailedInfo; coordinate: CLLocationCoordinate2D }` has two builders:
- `static func stops(from day: Loci_Trip_TripDay) -> (stops: [WalkStop], skipped: Int)`, which uses `DayTimeline.coordinate(of:)` rules.
- `static func stops(from group: DayGroup) -> (stops: [WalkStop], skipped: Int)`, which uses `DayGrouping.hasCoordinate`.

### `Features/Walk/Services/StopWalk.swift`
`@MainActor @Observable final class StopWalk` has a `static let shared`.
- **State:**
  - `title: String` (e.g. "Day 2 · Lisbon")
  - `stops: [WalkStop]`
  - `index: Int` (the stop being walked to, or the one just reached)
  - `phase: Phase` (`.idle`, `.walking`, `.arrived`, `.done`)
  - `skipped: Set<String>`
  - `navigator: WalkNavigator` (its own instance)
  - `tracker: WalkTracker` (its own instance)
  - `location: CLLocation?`
- **Actions:**
  - `start(title:stops:) async`
  - `walkToNext() async`
  - `skip() async`
  - `jump(to:) async`
  - `end() async`
- **Arrival:** the object observes `navigator.arrivedAt` through the `ingest` path and switches to `.arrived`. `WalkNavigator.ingest` ends navigation on arrival, and `StopWalk` checks `arrivedAt` after each ingest.
- **Location loop:** the same `CLServiceSession(.whenInUse)` + `CLLocationUpdate.liveUpdates()` loop as `NearbyWalk.start`, which feeds `navigator.ingest`.
- **Pure helpers** are `nonisolated static` for tests: the next index after a skip, the summary numbers, and the progress text.
- **Mutual exclusion:** `start` calls `await NearbyWalk.shared.stop()`, and `NearbyWalk.start` calls `await StopWalk.shared.end()`.

### Shared map layer: `Core/Navigation/UI/WalkMapLayer.swift`
This is extracted from `NearbyView`, which is then rewritten to use it.
- `@MapContentBuilder func walkLayer(navigator:location:heading:isMoving:)` draws the walker annotation (while navigating) or `UserAnnotation`, plus the route polyline (solid, or dashed for preview or straight line).
- `WalkCamera.follow(at:heading:) -> MapCameraPosition` returns 400 m, pitch 60.
- `WalkCamera.heading(location:navigator:)` and `isMoving(location:lastStepAt:)` are the helpers `NearbyView` has today.

### `Features/Walk/UI/WalkDayView.swift` + `WalkDayCard.swift` + `WalkStopList.swift`
- The map contains `walkLayer`, one numbered `Marker` per stop, and Recenter.
- Marker tint: done stops use `lociMutedInk` at 0.5 opacity, skipped stops use muted with a strikethrough label, the next stop uses `lociCoral`, and upcoming stops use the day colour.
- `WalkDayCard` renders the three phases (walking, arrived, done).
- `WalkStopList` is a sheet that lists the stops with their status. Tapping a row calls `jump(to:)`.
- The screen starts the walk in `.task` when `StopWalk.shared` is idle or walking a different day. If the same day is already running, for example after navigating away and back, the screen reattaches to it.

### Lock Screen card
Optional fields are added to `NearbyWalkAttributes`, so older payloads still decode:
- **Attributes:** `title: String?` (the static header, "Near me walk" when nil).
- **Content state:** `stopProgress: String?` ("3 of 6").

The widget shows the title and puts `stopProgress` before `destinationText`. The day walk fills the destination, distance and ETA fields while walking. When arrived it fills `destinationName = "At X"` with no distance or ETA. The places-count column is hidden when it is 0.

### Entry points
- **A, trip editor.** A **Walk** button (SF `figure.walk`) in every day header of `TripEditorView.daySection` pushes `WalkDayView(title: "Day N · City", stops: WalkStop.stops(from: day))`. It is disabled when no stop has a location. `TodayControls` stays where it is.
- **B, saved itinerary.** `SavedItineraryView` gets **Walk it**, which loads `SearchSessionController.shared.state(for: SessionLink(destination: .itinerary, sessionId:, domain: "itinerary"))`:
  - on `nil`, it shows "Couldn't load the stops for this itinerary";
  - with 1 day group, it pushes `WalkDayView` directly;
  - with more than 1, a day picker (confirmation dialog) comes first.
  The button is hidden when the itinerary has no `sessionID`.

## Errors and edges
- **No route.** The navigator already falls back to a straight dashed line, labelled as such.
- **Location denied.** The walk can't start, and the screen says "Allow location in Settings to walk this day".
- **Motion denied.** The walk runs without steps, as Near me already does.
- **The day changes while walking**, for example the trip is edited. The walk keeps the stops it started with. The trip editor is not touched.
- **App relaunch mid-walk.** The walk is not restored; it ends when the process dies. YAGNI: trip-day mode already covers being restored.

## Testing (Swift Testing, `lociTests/StopWalkTests.swift`)
- `WalkStop` builders: stops without a `poi` or at 0,0 are skipped and counted, and order is kept.
- `StopWalk` with a stubbed `Directions` closure:
  - `start` walks to stop 0;
  - an ingest at the stop moves to `.arrived` with a preview of the next stop;
  - `walkToNext` walks to index+1;
  - `skip` moves index+2 and records the skip;
  - `jump` walks to any index;
  - arriving at the last stop moves to `.done`;
  - `end` resets.
- The summary and progress text ("3 of 6", "6 stops (1 skipped)").
- Old `NearbyWalkAttributes` JSON (no title or `stopProgress`) still decodes.
- B: a `SearchState` fixture with 2 day groups maps to walkable stops per day.
- Existing `WalkNavigatorTests` and `NearbyWalkTests` still pass after the map-layer extraction.

## Out of scope
- Walking several days in one go.
- Restoring a walk after the app is killed.
- Spoken turn-by-turn directions.
- HealthKit (same decision as slice 20).
- Web.
- Changing trip-day mode.

## Delivery
- **PR A:** `WalkStop`, `StopWalk`, `WalkMapLayer` (with `NearbyView` moved onto it), `WalkDayView`, the Lock Screen fields, the trip-editor entry, tests, and the slice doc `docs/ios/23-walk-a-day.md (check the number is still free when the PR is cut; parallel sessions take them)`.
- **PR B:** the saved-itinerary entry, its test, and the doc updated.
