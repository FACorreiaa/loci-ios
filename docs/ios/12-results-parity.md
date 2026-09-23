# Slice 12: result pages at parity with web `/itinerary`

The first real search on TestFlight showed the model's raw JSON. The server
streams `token` events from three parallel workers; web never renders them, it
shows skeletons and then the parsed result. iOS now does the same, and the
result page mirrors web's `/itinerary` for all four domains.

Layout rule (user, 2026-09-23): Discover / itinerary results are a **map hero
plus list, tap to expand**; Nearby stays full map with the list in a sheet.
Web's phone List/Map toggle is not copied.

| Piece | Web | iOS |
|---|---|---|
| City header | `CityInfoHeader` (Pop / Area / Lang / Weather, "N/A") | `ResultsHeader`, redacted until `city_data` lands |
| Forecast + alerts + money | `LocalWeather`, `TripMoney` | `LocalContextStrip` ← `GetLocalContext{latitude, longitude, days: 5}`, `GetFxRates{latitude, longitude}` |
| Status rail | `ItineraryStreamView` | `StatusRail`: "Sketching your days…" / "Adding photos n/total" / "Itinerary ready · N stops" |
| Days | `groupStopsByDay` (server `day`, else 4 per day; first 2 days, then "Show the rest") | `DayGrouping`, `DaySection` |
| Stop card | `StopCard` (88px `image_credits[0]`, index stamp, rating, kicker, 2-line blurb, meta) | `StopCard`, `PlaceImage` (credited image first, gradient hashed from `stableID` when none) |
| Map | Mapbox, numbered day-coloured pins, dashed route per day, alert halos | `ResultsMapCard` (260pt, non-interactive, tap → `FullMapView` with the list in a detent sheet); MapKit `Annotation` / `MapPolyline` / `MapCircle` |
| "More to explore" | top-level POIs outside the plan | `SearchState.extras`, no day, no route |
| Detail | `DetailedItemModal` | `PlaceDetailSheet`: credited gallery with attribution + licence, stat tiles, `GroundedBadge`, `GetPlaceFacts{poiId}` (real id), contact rows, Save → `AddToFavorites{userId, itemId: poi.id, contentType by domain, cityName, latitude, longitude, rating, category, description}`, Share, Apple Maps, Google Maps |
| Trip Kit | `TripKit` | `TripKitView`: Apple Maps (per day), Google Maps multi-stop URL (≤ 8 waypoints, `lat,lng` or `name, address, city`), Add to Calendar (one EventKit event per stop, Day 1 09:00 on the chosen date, 90 min, 15 min buffer, `AppleCalendar.writeStops`), PDF → `ExportItineraryToPDF` then `ShareLink` |
| Pro gate | `isProPlan` (`premium_monthly`, `premium_annual`, `premium`, `pro`, `paid`, `explorer`) via `GetSubscription` | `ProGate`; free = Day 1 only with the "Unlock the full Trip Kit with Pro" line; a one-day list is free in full |
| Save / Share | device copy + `BookmarkItinerary`; `buildShareText` | Save = `ResultsAPI.bookmark` (the phone's copy is already written when the search finishes); Share = `ShareText.build` (title, ≤ 4 "Day N · a, b, c, d +k more" lines, "+N more days", "Generated from Loci", `https://lociai.fyi`) |
| Errors | error rail above the results | `SearchState.Status.completedWithError`: ERROR after places keeps them; `FailureRail` with Retry and "See Pro plans" on quota text |

Code: `Features/Search/Model/DayGrouping.swift` (grouping, share text, Google
Maps URL, calendar schedule, Pro gate), `Features/Search/Services/ResultsAPI.swift`
(the RPCs beside the stream), `Features/Search/UI/Results/*`.

## State changes

- `SearchState.phase` (`skeleton` / `enriching` / `done`) drives the rail.
- `COMPLETE` with `load_from_session = true` and nothing streamed → the
  controller fetches `GetChatSession` and adopts `current_itinerary`.
- `AiCityResponse.hotels / restaurants / activities` (proto v5.22) restore the
  list domains from the server and from the phone's copy; a copy saved before
  v5.22 still restores from `points_of_interest`.
- A partial result (places, then ERROR) is saved to the phone like a finished
  one, so the notification tap opens what there is.

## Not here

- `EditTripCTA`: `CompletePayload` carries no `navigation` in the Swift proto,
  so there is no `tripId` to link to.
- StoreKit / in-app purchase. The Pro line links to `/pricing`.
- Hotel and restaurant detail RPCs; the sheet uses the streamed POI.
- Typed-out text. Tokens now carry `part` (api #73) for a later pass.

## Checking it

`-designPreview results` renders a finished Rome itinerary offline (`resultsDays`
and `resultsKit` start scrolled to the days and the Trip Kit). No network calls
are made in a preview (`ResultsSideData.isOffline`).

Tests: `lociTests/ResultsParityTests.swift` (grouping, share text, Google Maps
URL, calendar timing, Pro gate, reducer partial-failure and `load_from_session`,
list restore, image choice, meta line).

Day colours: one palette on both, web's `LOCI_DAY_COLORS`, indexed the same
way (`day % 8` with the server's 1-based day, so Day 1 is pine teal; a list
with no days is day 0, coral; extras are the ungrouped grey). NATIVE_DESIGN
§map palette was updated to match.
