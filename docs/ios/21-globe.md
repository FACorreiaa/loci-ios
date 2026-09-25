# Slice 21: Where you've been (parity pass 2, Phase 7)

Web's `/globe` on iOS. Profile › You › Where you've been opens `GlobeView`
(the Phase 0 placeholder is gone). Read-only, one RPC web already calls.

## Screen → RPC

| Screen | RPC | Fields sent | Web source |
|---|---|---|---|
| Where you've been | `TravelHistoryService.GetGlobeData` | `limit 500`, `periodDays 365` | `lib/api/travel-history.ts` `getGlobeData` |
| See in Recents (city) | `RecentsService.GetRecentInteractions` | as Recents' Cities (`15-recents.md`) | none (web never wired `onSelectNode`) |

What the server does with it (`internal/domain/travelhistory/handler.go`
`GetGlobeData`):

- The caller comes from the token; the request has no user id.
- The first call for an account runs a one-off backfill from earlier trips.
  `backfilled` is true once that has run; a failed backfill is logged and
  reported as false, so the empty state says "not worked out yet" and offers
  "Check again".
- `limit` caps the cities and the legs separately (two queries). Legs come
  newest first, by the trip day's date (or the trip's creation when the day
  has none).
- Trends (proto v5.29.0, server api #101): `*_this_period` counts the last
  `periodDays` and `*_prev_period` the window before it, so a trend is this
  window against the last. Servers before that send zeros for `*_this_period`
  and cumulative totals as they stood `periodDays` ago in `*_prev_period`; there
  the arrow is the all-time total against that and only ever points up.
  `TravelSummary.hasWindowCounts` (any `*_this_period` non-zero) picks the rule,
  so the app works either side of the deploy. The catch: on a new server with
  nothing in the current window every count is zero, which reads as an old
  server and falls back to the total-based trend.
- Proto3 drops zero values; the Swift defaults already read them as 0 / "".
  A missing summary maps to all zeros and `periodDays 365`.

## Pieces

| File | What |
|---|---|
| `Features/Globe/Services/TravelHistoryAPI.swift` | `TravelHistoryAPI.globeData` over `rpc(…)`, `TravelHistoryService` protocol + `ConnectTravelHistoryService` |
| `Features/Globe/Model/GreatCircle.swift` | `geo.ts` ported: haversine, `path` (slerp, `clamp(ceil(deg/2), 24, 128)` segments, antimeridian unwrap), `segments` (cut at ±180 for MapKit), `midpoint`, `centroid` |
| `Features/Globe/Model/GlobeData.swift` | `GlobeCity`, `GlobeLeg`, `TravelSummary`, proto mapping, `GlobeLegKey`, `GlobeFormat` (`trendPercent`, `trendText`, `legLabel`, `nodeRadius`) |
| `Features/Globe/UI/GlobeView.swift` | `GlobeStore`, the map, city callout, states, `RecentCityLink` |
| `Features/Globe/UI/TravelStatsCard.swift` | web's StatsRail as a 2×2 card |
| `Features/Globe/UI/LegsSheet.swift` | web's ActivitiesDrawer as a detent sheet (stats on top, then legs) |

### The map

- MapKit `Map` with `.hybrid(elevation: .realistic)`, the camera asked for
  40,000 km out (MapKit clamps it), so it draws as a whole globe. It faces the
  spherical centroid of your cities, latitude kept within ±30° so a
  world-wide history stays upright. The map is only created after the first
  load: moving the camera once the map is on screen left MapKit zoomed far
  closer than the same camera given up front. The nav bar is forced dark over
  the globe (the imagery is dark in both appearances). The toolbar toggles a flat map
  (`.standard(elevation: .flat)`).
- Cities are `Annotation`s: a slate dot sized 4 → 9 pt radius by visits
  (web's `circle-radius` interpolation, 1 → 10 visits, clamped), inside a
  44 pt tap target.
- Legs are `MapPolyline`s in web's coral. Web unwraps longitudes past ±180,
  which Mapbox draws across the seam; MapKit does not, so
  `GreatCircle.segments` cuts the path at the antimeridian with a point on
  the seam at the interpolated latitude on both sides. Auckland → Santiago is
  two polylines with no gap and no streak across the map. The arcs are
  computed once per load in `GlobeStore.pieces`, not per frame.
- Tapping a leg (in the sheet) selects it, drops the sheet to its smallest
  detent, flies to the arc's midpoint at a distance scaled to its length, and
  shows web's label pill: `formatLegLabel`, "fly · 1,234 km · 2h 5m". Tapping
  it again clears it.
- Tapping a city shows a callout: country (when resolved), visits, last visit,
  and **See in Recents**.

### See in Recents

Recents knows the cities you *asked about*; the globe knows the cities you
*went to*. `RecentCityLink` loads Recents' Cities list and matches the name
case- and accent-insensitively (`RecentCityMatch`). A match pushes
`RecentCityView`; a miss says "Nothing in Recents for X" with "Open Recents"
(Cities segment). The sheet steps aside while it is pushed and comes back on
return.

### Leg identity

A `GlobeArc` has no id. Web keys legs by array index, so a new leg at the top
moves the selection onto a different leg. iOS keys by
`tripId|from|to|occurredAt` (epoch seconds, `-` when absent); the same leg
twice in one response gets `#2`, `#3` in the server's order.

## States

| State | Shows |
|---|---|
| Loading | "Loading your travels…" over the map |
| Error, nothing loaded | "Could not load your travels" + the message + "Try again" (web shows nothing) |
| Error on refresh | alert; the globe stays |
| Empty, backfilled | "No travels recorded yet" / "Cities appear here once a trip has real dates in the past, or once you mark a stop as visited. We don't guess from plans." (web copy) |
| Empty, not backfilled | "Not worked out yet" / "We haven't worked out your travel history yet. Check back shortly." (web copy) + "Check again" |
| Countries 0 with cities | "No country recorded yet" under Countries |
| No legs, some cities | the sheet says so under the stats |

Reduce Motion: there is no animated sweep (web's `useArcPlayhead` playhead is
not ported), and the camera cuts instead of flying; the callout fades rather
than slides.

Analytics: `Analytics.screen("globe")`.

## Web behaviour not copied

- Leg keys by index (above), and no error state (above).
- `onSelectNode` is declared on web's Globe and never passed: tapping a city
  does nothing there.
- The coordinate readout, mini-map and zoom buttons are left out: pinch,
  the compass and the scale bar do that job on a phone.
- The playhead sweep along the selected leg is not ported.

## Server gaps

- `GlobeArc` has no `duration_mins`, though `trip_legs` stores one, so the
  label never shows a time. `GlobeLeg.durationMins` is there for when it does.
- `GlobeArc` has no id, though `trip_legs.id` exists; the composite key above
  stands in for it.
- `country` is only set where a city resolved against the cities table, so
  "No country recorded yet" is common.

## Not on iOS yet

`TravelHistoryService` has six RPCs; this screen calls `GetGlobeData` and
`GetTravelSummary`. Not wired, on purpose (the plan asked for the globe, legs
and stats): `RecordVisit`, `DeleteVisit`, `ListVisitedCities`,
`ListVisitedPois`. So a stop cannot be marked visited from the phone; the
empty state says so and points at web. They are listed for parity pass 3
follow-ups.

## Tests and previews

`lociTests/GreatCircleTests.swift`: great-circle segment count and path (ends,
length against haversine, bowing north), antimeridian splits eastward and
westward and with a vertex on the seam, centroid across the seam,
`trendPercent` / `trendText`, `formatLegLabel` in `en_US` and `de_DE`, node
radius, leg-key stability under reordering and a new leg, duplicate legs,
missing-field defaults, the Recents city match, and `GlobeStore` phases.

Previews (Debug builds): `-designPreview globe` (seven cities, five legs, one
across the Pacific) and `-designPreview globeEmpty`, both offline through
`PreviewTravelHistoryService`; See in Recents uses `PreviewRecentsService`
(Lisbon and Porto match, Madrid does not).

## Not verified

Nothing here has run signed in against the live API: a real account's arcs,
the not-backfilled state (it lasts one request at most), and See in Recents
matching real city names. MapKit's globe needs Metal; the simulator
screenshots are the only rendering check.
