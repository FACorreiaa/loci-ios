# Slice 15: Recents (parity pass 2, Phase 1)

Web's `/recents` and `/recents/:city` on iOS. Profile › You › Recents and the
`loci://recents` app link both open `RecentsView` (the Phase 0 placeholder is
gone). Everything is read-only and uses RPCs web already calls.

## Screens → RPCs

| Screen | RPC | Fields sent | Web source |
|---|---|---|---|
| Recents › Feed | `RecentsService.GetInteractionHistory` | `userId`, `limit = 40 × pages` (≤ 200), `offset 0`, `sortBy "date"`, `sortOrder "desc"`; **no `InteractionFilter`** | `lib/api/recents.ts` `fetchActivityHistory` |
| Recents › Cities | `RecentsService.GetRecentInteractions` | `userId`, `limit 50`, `offset 0`, `groupByCity true` | `fetchRecentInteractions(50)` |
| City | none (the city comes whole from the Cities list) | | `routes/recents/[city].tsx` |
| A kept trip from the feed | `ItineraryService.GetUserItineraries` | `pagination{1, 100}` (Saved's call) | |

- `userId` is `AuthSessionManager.currentUserID` (stored at sign-in), not a
  decoded JWT. The server reads the caller from the token; the field is only
  there because validation requires it non-empty (`"me"` fallback, as Saved).
- The filter is never sent: its `city_id`/`search_query` have `min_len: 1` with
  no ignore rule, so a type-only filter is rejected. The chips and the search
  box narrow what has loaded; "Load more" widens the pool.
- `hasMore = entries.count < totalCount` (the server's count is a floor that
  says "one more exists"), and false once the limit reaches the proto's 200.

## Where rows go (`ActivityDestination`)

| Row | Opens |
|---|---|
| Prompt (itinerary, general, accommodation, dining, activities) | `SearchResultsView(link:rerunMessage:)` with `SessionLink{destination from the domain, sessionId, cityName, domain}` |
| Prompt, nearby, with a session | The same result page (Near me here is location-only and takes no city) |
| Prompt, nearby, no session | `NearbyView()` |
| Saved itinerary | `SavedItineraryView`, found in the Saved list by the row's id, then by session; gone from the list, the session's result page; neither, "Not in your saved itineraries" with "Open Saved" |
| Favourite (poi, hotel, restaurant) | `SavedPlaceDetailView` on a `FavoriteItem` built from the row (id, item id, name, city, content type); it enriches from the server as it does from Saved |
| Favourite, itinerary | The saved itinerary, as above |
| Unknown kind | Nothing (the row shows, not tappable) |

Web's whole feed turns on the message riding along: a session that cannot be
restored re-runs from `?message=`. `SearchResultsView` now takes
`rerunMessage`; when the session is not found it shows "Run it again", starts
the prompt as a new search (not a follow-up in the old session) and follows the
session the server names (`startedLink`). A prompt with no session skips the
restore and goes straight to that state. Web also passes `profileId`; iOS
does not need to, because `SearchSessionController.start` resolves the default
profile itself.

## Pure helpers (`Features/Recents/Model`)

| Helper | Web | Notes |
|---|---|---|
| `ActivityFeed.entry` | `mapActivityEntry` | kind from `metadata.kind` (missing → prompt, unknown → `.other`); detail = content type (favourite, default poi), "itinerary" (save), `entityType` (prompt, default general) |
| `ActivityFeed.stripPromptWrapper` | `prompt-wrapper.ts` | same anchored, case-insensitive regex |
| `DayBuckets.bucket` / `relativeTime` | `day-buckets.ts` | local-midnight day math through an injected `Calendar` |
| `ActivityTypeOption` / `ActivityFilter` | `ActivityTypeChips.tsx`, `recents/index.tsx` | (kind, detail) chips, counts over what loaded |
| `ActivityBadge` | `ActivityRow` `descriptorFor` | SF Symbols for lucide icons |
| `RecentCities.extractMessage` / `CityActivityLevel` | `recents.ts`, `CitiesView.tsx` | ≥ 10 very active, ≥ 5 active |

Web bugs deliberately not copied:

- An entry with no timestamp is dated "now" on web (so it files under Today);
  here it is undated and files under Earlier with no time.
- `extractMessage` appends the city whenever the message does not *end* with
  it, doubling it after a full stop ("Itinerary in Funchal. Funchal"); here the
  city is added only when the message does not mention it.
- The Cities sort has no tiebreak on web; here equal times fall back to the name.
- Cities errors are thrown, not swallowed into an empty list (web shows "No
  recent activity" when the API is down).
- The city page has only Overview and Interactions. Web's Places, Favorites and
  Saved Itineraries tabs and its hotel/restaurant/attraction tiles are always
  empty (the server never fills them); `country` is always empty too, so the
  Country row only appears if the server starts sending it.

## States

Feed and Cities each have a skeleton (six redacted rows), an error with
"Try again" (web copy: "Could not load your activity" / "The history is still
there. This is on our side."; Cities: "Unable to load recent activity" /
"Please try again later"), and two empty states: unfiltered ("No activity yet"
/ "Everything you ask, save or favourite shows up here." with "Start
exploring" → Discover tab; Cities: "No recent activity" / "Start exploring
cities to see your activity here!") and filtered ("Nothing of that kind yet" /
"Try another type, or clear the search."; "No cities found"). A failure with
rows already on screen is an alert and the rows stay. Pull to refresh reloads
the current segment.

Analytics: `Analytics.screen("recents")` and `Analytics.screen("recents_city")`
(PostHog `$screen`; the wrapper gained `screen(_:)` for this).

## Tests and previews

`RecentsBucketsTests`, `ActivityMappingTests`, `ActivityDestinationTests`
(web's `day-buckets.test.ts` and `activity-link.test.ts` ported, plus the
mapping, paging, chips and city helpers). Previews (Debug):
`-designPreview recents`, `recentsCities`, `recentCity`, all offline through
`PreviewRecentsService`.

## Not verified

Nothing here has run signed in against the live API: the feed's real rows,
each row's destination (especially favourites keyed by name, and nearby
sessions restoring through `GetChatSession`), and "Run it again" on a session
that no longer restores.
