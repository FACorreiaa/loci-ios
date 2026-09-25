# Slice 20: Contribute (parity pass 2, Phase 6)

Profile › Contribute is web's `/contribute`: the scout's standing, the places
the server wants a fresh look at, places somebody else proposed, and a way to
report on, or add, a place that isn't on the list. Place detail gets a
"Report a fact" button that opens the same form for that POI.

The server corroborates two claims only when the values are the **same
string** (`LOWER(value) = LOWER(value)` across two scouts). So the
vocabulary and the opening-hours encoding are ports of web's, one to one, with
web's tests, and the token lists are checked against the server's
`placeintel/values.go` in a test of their own.

## Screens → RPCs

| Screen | RPC | Fields sent |
|---|---|---|
| Contribute › hero | `PlaceIntelligenceService.GetMyContributorProfile` | none |
| Contribute › Places that need a fresh look | `ListVerificationTasks` | `limit: 40` (paged 5 per page on the client) |
| Contribute › Does this place exist? | `ListPendingPlaces` | `limit: 20` |
| … › Yes, it exists | `ConfirmPlace` | `submissionId` |
| … › Something we're missing | `PoiService.SearchPOI` | `query`, then either `latitude`, `longitude`, `radiusKm: 25`, `searchType: "hybrid"`, `cityName` (typed or reverse-geocoded, else `"nearby"`), or `searchType: "semantic"`, `cityName` (typed). Top 5 kept |
| Field report › Submit | `SubmitPlaceClaim` × one per answer, in parallel | `clientClaimId` (fresh UUID per claim), `poiId`, `field`, `value`, `observedAt: now` |
| Add a place › Add this place | `SubmitPlace` | `clientSubmissionId` (stable per draft), `name`, `cityName` (trimmed), `category` only when set |
| Place detail › Report a fact | as Field report | every contributable field for that POI |

- Several answers are several claims (web's `useSubmitPlaceClaims`). The card shows the best status any reached: ACCEPTED, then PENDING, then the first. One failure fails the report, as web's `Promise.all` does.
- The draft id stays the same until a field actually changes, so a retry after a dropped response is a repeat, not a second place. After a submit the name and kind clear and the city stays.
- Location is read only when it is already allowed. Contribute never asks for it.

## Rules (`Features/Contribute/Model`)

- **Vocabulary** (`PlaceFactVocabulary`): web's labels, questions and tokens; `claimValues` trims, lowercases, de-duplicates, drops empties and sorts; a single-answer field keeps the first.
- **Picking** (`PlaceFactVocabulary.toggle`, web's FieldPicker): single choice picks or clears; "None of these" clears the rest and anything else clears it; Vibe keeps three and drops the oldest.
- **Opening hours** (`OpeningHours`): Monday first, intervals sorted and merged (touching ones too), identical consecutive days collapsed (`mon-fri 09:00-17:00; sat-sun closed`), midnight close `24:00`. `parse` returns nil rather than guessing. The editor shows one span per day, as web's does.
  - The time pickers run in GMT and `en_GB`, so the device's zone, daylight saving and a 12-hour locale can't change the string. The wire format is 24-hour either way.
- **Who can report:** `ContributePayload.canReport` is Add to list's and Reviews' rule (a real, non-nil POI UUID). The handler parses `poi_id` and checks it exists. A search result that isn't stored shows "Not reportable".
- **Tasks:** fields this build doesn't know are dropped (web does the same). A searched place already on the gap list keeps its fields (`resolveTask`); any other gets every field.
- **Badges:** shown under the hero stats. Web fetches them and never shows them. The server awards one, `local-scout`, at ten verified reports.
- **Stored facts:** the place detail's "Verified by travellers" list now shows the option label ("Gluten free") instead of the raw token.

## State

- `ContributeStore`: tasks drive the page state (skeleton, error with retry, "Nothing queued right now"). The profile and pending feed are extras, so their failures leave them empty. Confirmed places stay on the page with their outcome after the refetch drops them (web's `confirmed` map).
- `ClaimFormStore`: field, answers, week, result. Changing field clears the answers and the result. After a submit the answers clear, so the same report can't be sent twice by accident.
- `AddPlaceStore`: the draft and its result message.
- All three take a `ContributeService`: `ConnectContributeService` is the live one, and `PreviewContributeService` serves previews and tests.

## Analytics

- `place_claim_submitted {field, status, poiId, answers}`, with `field` as the proto enum name and `status` as web's word (`ACCEPTED`…), exactly as web sends them.
- `place_submitted {city}`.
- Screens: `contribute`, `claim_form {fields}`, `add_place`.

## Server and web gaps

| # | Gap | Effect | Fix |
|---|---|---|---|
| 1 | `SearchPOIRequest.city_name` is `min_len: 1`, but the handler has a no-city semantic branch and ignores the city on hybrid. **Web's MissingPlaceCard always sends `cityName: ""`**, so its search fails validation in production every time (probed unauthenticated 2026-09-24: `invalid_argument … city_name: must be at least 1 characters`; with a city the same probe reaches auth). | iOS sends a typed or reverse-geocoded city, or `"nearby"` on a hybrid search, and needs a typed city when location isn't allowed. | Relax `city_name` to optional (IGNORE_IF_ZERO_VALUE), or make web send a city (Phase 8) |
| 2 | Claims give no read-back: there is no "my claims" RPC. | A scout can't see earlier reports or their status. The result card shows only the report just filed. | `ListMyClaims` |
| 3 | `ContributorProfile.badges` are bare slugs with no title or rule. | iOS has the one known slug hard-coded and shows others as words. | a badge message with title and description |
| 4 | `ConfirmPlace` by the submitter is FailedPrecondition, but pending places already exclude your own, so this only shows on a race. | none | none |

## Review follow-up (after #35)

Four things the review found, all in what a scout sees:

- **Refusals read as sentences.** `ContributeError` (`Model/ContributeError.swift`)
  keeps the Connect code the three writes answer with and turns each into one
  line: AlreadyExists → "“Foo” is already on the guide. Search for it above.",
  FailedPrecondition → the server's reason as a sentence, Unimplemented →
  "Contributions are switched off right now", Unavailable → offline wording,
  anything else → the action's own fallback. Web still shows the raw message.
- **A confirm that cannot succeed loses its button.** `confirmFailed` keeps
  the error per submission; `canRetry` is false for FailedPrecondition (no
  coordinates yet, your own place), so the card shows the reason and no "Yes,
  it exists".
- **Midnight closes.** A close picked at 00:00 becomes `24:00` (`setTime`),
  and each day that cannot be sent says why under its row (`problem(_:)`).
  Past-midnight spans are still unsupported by design. The same week cannot
  be filed twice by accident: Submit waits for a change.
- **The City field wins.** With location on, a City other than the located
  one runs a semantic search in that city instead of "within 25 km of you"
  (`ContributePayload.searchCoordinate`).

A filed report now reloads the task list as well as the profile, so the
place's open questions update.

## Tests and previews

`lociTests/ContributeModelTests.swift`: claim values, vocabulary (including
the server token table), field picking, opening hours (encode, parse, validity,
editing, the GMT clock), paging, `resolveTask`, best status and outcomes,
request builders, draft ids, and the three stores against the offline service.

Previews (Debug, offline):

- `-designPreview contribute`
- `claimForm` (Vibe, just filed: "Recorded." with the scouts bar)
- `openingHours`

## Not verified

- Nothing has run signed in against the live API: tasks, profile, pending, confirm, claims, add place, and the plan's two-account check (an hours claim, then a second account corroborating it to "Verified").
- The missing-place search with a real location and reverse geocoding.
- Dynamic Type XL was not checked.
