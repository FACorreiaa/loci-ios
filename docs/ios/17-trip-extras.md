# Slice 17: trip page extras (parity pass 2, Phase 3b)

The trip page now has everything web's `/trips/:id` has: the hero, the
preferences disclosure, the export menu with its Pro gate, and checklists.
The checklists sync through the server, not local storage, so a tick on the
phone shows up on web once web moves off localStorage (Phase 8). Add to trip
from a place is Phase 3c and is not in this slice.

`TripEditorView.swift` was one 382-line view. It is now split the way web's
components are:

| iOS | Web | File |
|---|---|---|
| `TripHero` | `components/trip/TripHero.tsx` | `Features/Trips/UI/TripHero.swift` |
| `TripPreferencesSection` | `components/trip/TripPreferences.tsx` | `Features/Trips/UI/TripPreferencesSection.swift` |
| `TripExportSection` | `components/trip/TripExportMenu.tsx` | `Features/Trips/UI/TripExportSection.swift` |
| `TripChecklistsSection` + `TripChecklistStore` | `components/trip/TripChecklists.tsx` | `Features/Trips/UI/TripChecklistsSection.swift`, `Features/Trips/Model/TripChecklistStore.swift` |
| `StopRow`, `PlacePicker` (moved, unchanged) | `PlacePicker` | `Features/Trips/UI/StopRow.swift` |
| `TripAPI` (moved out of `TripsView.swift`) | `lib/api/trips.ts`, `lib/api/packing.ts` | `Features/Trips/Services/TripAPI.swift` |

## Screen → RPC → fields

| Screen | RPC → fields sent |
|---|---|
| Open the page | `GetTrip{tripId}`, `GetTripChecklist{tripId}`, `SuggestPacking{tripId}`, `GetSubscription{}` (the plan, via `ResultsSideData`), all at once |
| Preferences (pace, budget, mobility, day start/end) | `SetConstraint{tripId, constraints: current merged with the one change, baseVersion}` |
| Export › .ics / PDF / Markdown | `ExportTrip{tripId, format}` → temp file → `ShareLink` |
| Share | `ShareTrip{tripId, isPublic: true}` |
| Add / tick / un-tick an item, add an expense | `UpsertChecklistItem{tripId, item{id: client UUID, kind, text, done, amountMinor, currency, position}}` |
| Swipe to remove | `DeleteChecklistItem{tripId, itemId}` |
| Suggestion × | `DismissPackingSuggestion{tripId, text}` |
| Suggestion + / Add all | `UpsertChecklistItem` per item |

## Rules worth knowing

- **Hero.** It shows "Route · N days", the title, the city and
  `TripFormat.tripDates` ("4 Oct", "4–6 Oct", "30 Sep – 2 Oct"). A day's date is
  a Timestamp at midnight UTC, so it is read as a calendar day
  (`DayTimeline.localMidnight`). Formatting it as an instant would print the
  day before anywhere west of Greenwich. The day headers use the same helper now.
- **Preferences.** Each control sends one `PreferencePatch`, and
  `TripFormat.merged` applies it to the current constraints. Optional fields
  are cleared, never sent empty: `mobility` has `min_len: 1`, so an empty
  field would fail validation. A second tap on the selected budget clears
  it. Edits are queued, so each one sends the `version` the previous one
  returned. The time pickers wait 700 ms before sending, so one wheel spin
  sends one request, not twenty.
- **Conflicts.** The server answers a stale `baseVersion` with
  FailedPrecondition. `TripRPCError.isVersionConflict` (FailedPrecondition or
  Aborted) turns that into the "This trip changed on another device" alert,
  and its Reload button fetches the trip again. This covers every stop edit,
  not just preferences.
- **Export gate.** `TripExportGate` works like web's menu:
  - `.ics` always exports. On a free plan with more than one day the page
    shows "Day-1 calendar works free…", **but the server does not trim the
    .ics** (`trip/handler.go` returns `buildICS(t)` for every plan; only the
    PDF is trimmed). Web makes the same claim. Open decision: trim on the
    server or drop the notice on both clients. Until then the notice
    under-promises.
  - PDF on a free plan with more than one day is locked: the server is not
    called, and the page says why.
  - Markdown is Pro only.
  - The copy never names a price or links to pricing (App Store 3.1.1); a test
    checks this.
  - A PermissionDenied from the server gets the same neutral line.
  - `trip_exported{format, day_count}` fires after the file is written.
- **Share.** It now sends `share_link_created{content_type: "trip"}`, as web
  does. It sent nothing before this slice.
- **Checklists.**
  - Every edit is optimistic. On failure, only the item that failed is put
    back (a new item goes away, a toggled one gets its old value, a deleted one
    returns to its place), so two quick edits can't undo each other.
  - Item ids are client UUIDs, so a retried upsert does not create a
    duplicate.
  - The checklist has its own version and takes no `baseVersion`, so ticking
    an item never conflicts with a stop edit.
  - ResourceExhausted means the 500-item cap; the store also checks the cap
    before sending.
- **Open suggestions.** `TripChecklist.openSuggestions` hides a suggestion
  when its text (trimmed, case-insensitive) is already a packing item or has
  been dismissed. The server stores dismissals lowercased and trimmed.
  Expenses do not count as packed.
- **Money.**
  - Amounts are stored as `amount_minor`, the scale taken from the currency (100
    for EUR, 1 for JPY), and either decimal mark is accepted.
  - Trips have no currency field. New expenses use the currency already on the
    trip's expenses, then the phone's region currency, then EUR.
  - Totals are per currency and are never added across currencies
    ("€12.50 + £3.00").
- **Before the server deploy.** Until the checklist RPCs reach production,
  `GetTripChecklist` answers Unimplemented. The store then sets `.unavailable`:
  - no alert;
  - the packing section shows one line of copy, and the expense section is
    hidden;
  - suggestions stay read-only;
  - nothing is sent.
- **When the load fails for any other reason** (review follow-up to #31):
  - the phone's last confirmed copy (`LocalCache.Kind.checklist`, written on
    every successful load) is shown read-only as `.cached`, with a Retry;
  - with no copy, the section is `.failed(message)` with a Retry, and the
    expense section stays hidden;
  - a refresh that fails on an already confirmed list keeps it editable and
    raises the alert (which lives on `TripEditorView`, not on the section's
    `Group`, so it is attached once);
  - a failed edit only rolls back while the item on screen is still the one
    that failed (`TripChecklist.shouldRollBack`), so a later edit that landed
    is never undone by an older failure. There is no offline queue: a tick
    made offline fails and reverts.

## Offline trip cache

The page uses the app-wide cache from the offline trip day slice
(`14-offline-trip-day.md`), not a cache of its own. An earlier draft of this
slice ported web's `lib/trip-offline-cache.ts` as a per-user, 12-trip JSON
LRU; it was dropped when rebasing onto #29 so there is one trip cache on the
phone.

- `load()` reads the trip through `cacheThrough(kind: .trip, id: tripID)`
  (`Core/Cache/Loaded.swift`): the serialized `TripDraft` in `LocalCache`
  draws at once, then `GetTrip` replaces it and the copy is rewritten. The
  plan (`ResultsSideData.loadPlan`) and the checklists load alongside it.
- If `GetTrip` fails and a copy exists, the result is `.stale`: the page draws
  the copy, shows the `CacheChip` ("Offline · last updated …" or "Saved …")
  under the hero, and says "Connect to edit".
- A stale or missing copy makes the page read-only (`canEdit`): Edit is
  disabled (and switched off if it was on), rows cannot be moved, the swipe
  actions are gone, and the preferences disclosure is disabled. The
  checklists keep their own `TripChecklistStore.canEdit`.
- Every trip an edit returns is adopted as `.fresh` and written back to
  `LocalCache`, so the copy always follows the server's latest `version`.
- The conflict alert's Reload runs the same cache-through read.
- Any end of session (sign-out, dead refresh token, account deletion) clears
  the whole cache (`LocalCache.shared.clear()` in `AuthService.logout` and on
  `authSessionDidInvalidate`). The cache is not keyed per user; clearing on
  every session end is what keeps one account's trips from another.
- The day headers keep the Today controls (`TodayControls`) from #29 on the
  day dated today.

### Trip dates

A day's date is a calendar date carried as a Timestamp. Web writes midnight
UTC; older app builds wrote local midnight. Every reader goes through one
helper, `DayTimeline.localMidnight(of:)`, which rounds to the nearest UTC
midnight and places that calendar day at local midnight. `TripFormat.tripDates`
(the hero range), the day headers and the Today band all use it, so the page
and the Today band never disagree about which day is which, east or west of
UTC.

## Tests (`lociTests/TripFormatTests.swift`)

| Suite | Covers |
|---|---|
| `TripFormatTests` | Eyebrow plural, `tripDates` for none, single, same month and cross month, a midnight-UTC day read in New York, a local-midnight day read in Athens, minutes ↔ HH:MM ↔ picker date, pace and budget labels, collapsed badges, the second tap clearing the budget, merges that clear empty optionals |
| `TripExportGateTests` | ICS always (with a notice on a free multi-day trip), PDF Pro past one day, Markdown Pro only, no price or link in any copy, web's analytics names, filename sanitising |
| `TripChecklistTests` | `openSuggestions` (case, trim, dismissed, expenses not counted, duplicates), packed summary, order and next position, `makeItem` trim, cap and UUID, amount parsing (both marks, JPY, rounding, rejects), default currency, per-currency totals |
| `TripChecklistStoreTests` | Load, Unimplemented is quiet, failed load is retryable, cached copy read-only when unreachable, successful load cached, adopt the server copy, and rollback for add, toggle, delete and dismiss (never over a later edit); Add all order, expense minor units and rejects, nothing sent while unavailable |
| `TripRPCErrorTests` | Conflict, unimplemented and cancelled codes |

## Design previews

- `-designPreview tripExtras` shows a three-day Lisbon trip, offline, on a free
  plan: hero, preferences open, the days, export, suggestions, packing and
  expenses.
- `-designPreview tripChecklists` shows the checklist sections alone.

## Not verified yet

- There has been no signed-in run against the live API. The checklist RPCs
  are live on the server.
- The offline path (airplane mode on an opened trip) has not been run on a
  device since the rebase onto #29.
- Once deployed, a tick needs checking in both directions against web. Web
  won't read the server checklist until Phase 8.
- The export share sheet and the Apple Calendar write have not been run on a
  device in this slice.
- Dynamic Type XL has not been checked.
