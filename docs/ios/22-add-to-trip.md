# Slice 22: Add to trip (parity pass 2, Phase 3c)

Place detail gets "Add to trip" (calendar.badge.plus, next to Add to list),
for a search result, a saved place and a list row alike. It opens a sheet with
your trips and their days; the place goes on the day you pick. Web's
equivalent is `components/trip/AddToTripButton.tsx`.

Everything lives in `Features/Trips/AddToTrip/`. Nothing under
`Features/Trips/UI` changed; the sheet pushes `TripEditorView(tripID:)` and
`TripsView()` as they are. It has its own TripService client
(`AddToTripAPI`), so it does not depend on the editor's `TripAPI`.

## Screens → RPCs

| Step | RPC | Fields sent |
|---|---|---|
| Sheet opens | `TripService.ListTrips` | `pagination {page 1, pageSize 50}` (TripsView's page) |
| Add to Day N | `GetTrip`, then `AddStop` | `tripId`; then `tripId`, `dayId` (resolved in the fresh trip), `baseVersion` = the fresh `version`, `stop` (below) |
| Stale version | `GetTrip`, `AddStop` once more | same, re-read |
| No trips › Create a {city} trip | `SaveTrip` | `baseVersion 0`, `trip {userId: current user or "self", cityName, cityId when the place has a real one, title "{city} trip" / "My trip", pace moderate, days: [Day 1 with the place]}` |

The stop (`TripStopBuilder`): `id` a fresh lowercase UUID, `poiId` only when
the place has a stored POI UUID, `orderIndex` = the day's stop count, `name`
(trimmed, ≤ 300, "Saved place" when empty), `notes` = rationale, else
`description_poi`, else `description`, else "Added from Loci" (≤ 4000),
`recommendationTrace` when the place carries one.

- **TripStop has no coordinates.** The server fills `stop.poi` (and so the
  editor's pin) from `poi_id` when it names a stored place. A name-only stop
  (a saved place with no POI id, an unstored search result) goes in by name
  and notes and has no pin. That is why the button shows for every place,
  unlike Add to list.
- The handler ignores the stop `id` and `orderIndex` we send (it appends and
  lets the database assign the id). We send them anyway, as web does.

## Web's two stale bugs, and what iOS does instead

1. **Version.** Web sends `trip.version` from its cached `useTrips` list, and
   stop mutations update only the trip's detail query (`lib/api/trips.ts`
   `detailMutation`), so a second add in a row is refused with
   `FailedPrecondition`. iOS reads the trip with `GetTrip` immediately before
   each `AddStop`, and on `FailedPrecondition` (`AddToTripError.staleVersion`,
   caught before the Connect error is flattened) reads and tries once more.
   A second refusal says the trip changed on another device.
2. **Day id.** `SaveTrip` in the repository deletes and re-inserts
   `trip_days`, so **every edit gives every day a new id**. Web holds the day
   id from the list; after any edit it no longer exists and the handler says
   "day not found". iOS selects the day by `dayNumber` and resolves the id in
   the fresh trip (`AddToTripPayload.addStop(to:dayNumber:)`). A day number
   that is gone reloads the list and says so (`AddToTripError.dayMissing`).

After a success the sheet shows "✓ Added to Day N" with "Open trip", which
pushes the editor in the sheet's own stack.

## Edit trip CTA on results

`CompletePayload` has no trip id in the Swift gen (chat.proto: `session_id`,
`result`, `load_from_session`). The server puts it on the event's envelope
instead: `StreamEvent.navigation` (`/trips/:id`, `queryParams.tripId`) when it
auto-saved the itinerary (`chat_process_stream.go sendCompletionEvent`). That
field is in the Swift gen, so `SearchState` reads it on COMPLETE
(`SearchState.tripID(from:)`, web's `tripIdFromNavigation`) into
`savedTripID`, and `ResultsPage` shows "Trip saved · {city}" with "Edit
trip", which opens the editor in a sheet. A result restored from the phone's
copy or from `GetChatSession` has no COMPLETE and so no banner.

## Analytics

`trip_stop_added {source: "place_detail"}` on each add, with `new_trip: true`
when it started one. Web sends no event for this yet. `Analytics.screen("add_to_trip")`.

## Tests and previews

`lociTests/AddToTripTests.swift`: the stop builder (stored vs name-keyed,
notes order, limits, trace), the requests (ListTrips page, AddStop from a
fresh trip by day number, the new trip), the day label (UTC date, other city),
the retry (read first; stale → re-read with the new version *and* the new day
id; a second stale gives up; a missing day is not retried; two adds in a row
against the preview service), the store (defaults, the day survives an add,
create when empty), and the trip id from COMPLETE's navigation.

Previews (Debug, offline through `PreviewAddToTripService`, which bumps the
version and renames days on every save like the server):
`-designPreview addToTrip`, `-designPreview resultsTripSaved`.

## Not verified

Nothing has run signed in against the live API: the add itself, the stale
retry against a real second device, "Create a trip" (`SaveTrip` validation of
`user_id`), and the Edit trip banner (needs a search the server auto-saves).

Found on the way, not fixed here: Compare's "save as trip" builds a
`TripDraft` with no `user_id`, which `min_len: 1` should refuse at validation.
