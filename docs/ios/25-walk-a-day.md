# Slice 25: Walk a day (stop by stop, Near me style)

Near me directions (slice 20) walk you to one place. This slice walks a whole day: the route to stop 1, a pause when you get there, then the next stop when you say so. Two ways in: the **Walk** button in each day header of a trip, and **Walk it** on a saved itinerary. It needs no new RPCs and no server changes. Directions are Apple's (`MKDirections`, walking), so they are free and need no key.

Spec: `docs/superpowers/specs/2026-09-25-walk-a-day-design.md`. Plan: `docs/superpowers/plans/2026-09-25-walk-a-day.md`.

| Piece | Apple SDK | Where | Notes |
|---|---|---|---|
| A walkable day | none | `Features/Walk/Model/WalkStop.swift` | `WalkDay.from(trip:day:)`, `from(group:sessionId:cityName:)`, `days(from: SearchState)`. Stops without a usable coordinate (no `poi`, or 0,0) are dropped and counted (`withoutLocation`). |
| Walking the stops | CoreLocation `liveUpdates`, CoreMotion (`WalkTracker`) | `Features/Walk/Services/StopWalk.swift` | Phases: idle → walking → arrived → … → done. Arriving within 25 m pauses the walk and previews the next leg. Actions: **Walk to next**, **Skip**, jump from the stop list, **End**. Its own `WalkNavigator` handles rerouting (> 40 m off twice, at most every 10 s). Tests construct it with `live: false`: no hardware. |
| Map | SwiftUI MapKit | `Core/Navigation/UI/WalkMapLayer.swift`, `Features/Walk/UI/WalkDayView.swift` | Near me uses the same walker, route line and follow camera (400 m, pitch 60, Recenter after a pan). Pins are numbered: coral for the next stop, faded once done or skipped. |
| Card and stop list | SwiftUI | `WalkDayCard.swift`, `WalkStopList.swift` | Walking: "→ 3 of 6 · Café X · 400 m · 5 min · steps". Arrived: "You're at X (3 of 6)", "Next: Y · 8 min", Walk to next / Skip. Done: "Day walked · 6 stops (1 skipped) · 5.2 km · steps". |
| Lock Screen | ActivityKit | `Shared/NearbyWalkAttributes.swift`, `NearbyWalkWidget/NearbyWalkLiveActivity.swift` | This slice adds optional `title` ("Day 2 · Sintra") and `stopProgress` ("3 of 6") to the Near me card. Older payloads still decode (tested). |
| Arrival with the phone locked | UserNotifications | `StopWalk.notifyArrival` | Posts "You're at X (3 of 6)" only when the app is not active. |
| Saved itinerary entry | none (existing restore path) | `SavedView.swift` `SavedItineraryView` | A saved itinerary is only text. **Walk it** restores the search that made it (`SearchSessionController.state(for:)`) and walks its `dayGroups`: one day goes straight in, more than one shows a day picker, and none shows "Couldn't load the stops for this itinerary". |
| Design preview | none | `Core/DesignPreview.swift` `.walkDay` | `-designPreview walkDay` (Debug builds): four stops in Lisbon's Baixa with no sign-in. Drive it with `xcrun simctl location <id> set <lat>,<lon>`. |

## Decisions
- **Arrival pauses.** You spend time at a stop, and the route to the next one starts when you tap.
- **Any day can be walked**, dated or not, today or not.
- **Trip-day mode runs alongside, untouched.** Its schedule, reminders and Lock Screen card keep going, so two cards can show.
- **One walker at a time.** Starting a day walk ends a Near me walk, and the other way round, so only one location loop runs.
- **Not restored after the app is killed.** Trip-day mode already covers relaunch.
- **No HealthKit** (see slice 20).

## Verified
- Tests (`lociTests/StopWalkTests.swift`, 18 tests):
  - day building and skipping stops without a location;
  - card text and old payloads decoding;
  - the whole `StopWalk` state machine, including starting on top of stop 1, a one-stop day, skipping the last stop, and two stops at the same spot;
  - the Lock Screen state for each phase;
  - `isMoving`;
  - saved itinerary to walkable days.
- Full suite 596/596 after the review fixes. SwiftLint clean.
- Simulator (`-designPreview walkDay`, Lisbon):
  - walking card, numbered pins, walker and no-location note;
  - moving onto stop 1 arrives, fades pin 1, turns pin 2 coral and shows the arrived card. The first layout truncated the Walk to next button; that was fixed and checked again.

## Not verified
- Tapping **Walk to next**, **Skip** and the stop list in the simulator. `simctl` can't tap; the unit tests cover the state changes.
- A real walk on a phone: steps, the follow camera while moving, the arrival notification with the phone locked, and battery use.
- **Walk it** from Saved: that needs a signed-in account.
- Which way the walker faces when moving (still the slice 20 guess, `WalkingRoute.symbolFacesRight`).

## Deferred from the final review (minor)
- The map pins come from the screen's `day.stops`, while their colour comes from the walk. If a trip day is edited mid-walk and reopened, the two can disagree.
- The Lock Screen card says "Day walked" until its first refresh, because the activity is requested while the walk is still idle.
- Live Activities left behind when the app is killed mid-walk are never cleaned up. Near me has the same gap.
- Popping the screen during the first route fetch can leave a straight-line route.
- A tab switch during start (`CancellationError`) shows an error alert.
- Walk it on a search that is still streaming can use a partial result. A multi-city itinerary only offers the first city's days.
- The same place twice in a saved itinerary day (e.g. the hotel first and last) gives duplicate ids, which breaks the `ForEach`.
- The `walkDay` design preview starts a real walk and Live Activity.
