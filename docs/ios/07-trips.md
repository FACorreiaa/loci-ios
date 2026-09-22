# Slice 7: Trips

| iOS | Web | Service | RPC → fields sent |
|---|---|---|---|
| My trips (Calendar tab › list) | `/trips` | `TripService` | `ListTrips{pagination{1, 50}}` |
| Editor | `/trips/:id` | `TripService` | `GetTrip{tripId}` |
| Reorder (Edit › drag) | drag | | `ReorderStops{tripId, dayId, orderedStopIds, baseVersion}` |
| Rename (swipe) | | | `RenameStop{tripId, stopId, name, baseVersion}` |
| Duration stepper (Edit) | | | `EditStopDuration{tripId, stopId, startMinute?, durationMinutes, baseVersion}` |
| Pace | constraints | | `SetConstraint{tripId, constraints{pace, …unchanged}, baseVersion}` |
| Add a place (Edit › search) | `PlacePicker` | `PoiService` + `TripService` | `SearchPOI{query, cityName, searchType: "semantic"}` then `AddStop{tripId, dayId, stop{id, poiId, orderIndex, name, notes}, baseVersion}` |
| Replace (swipe) | | | `ReplaceStop{tripId, stopId, replacement, baseVersion}` |
| Remove (swipe) | | | `RemoveStop{tripId, stopId, baseVersion}` |
| Share | | | `ShareTrip{tripId, isPublic: true}` → `ShareLink` with the URL |
| Export | `TripExportMenu` | | `ExportTrip{tripId, format: ics/pdf/markdown}` → file, `ShareLink` |
| What to pack | | | `SuggestPacking{tripId}` |
| Add to Apple Calendar | | EventKit | existing `AppleCalendar.writeTrip` |

Every edit adopts the `TripDraft` the server returns; its `version` is the next `baseVersion`, so a conflicting edit from another device fails instead of merging. Pro-only export limits are enforced by the server and shown as its error.
