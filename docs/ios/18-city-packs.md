# Slice 18: City Packs (parity pass 2, Phase 4)

Web's `/packs` and `/packs/:slug` on iOS: ready-made, day-by-day city trips.
Discover › City Packs and the `loci://packs/:slug` app link open them (the
Phase 0 placeholders are gone). A pack you can read in full can be opened as
your own trip; a paid pack you have not bought shows its preview and nothing
to buy.

## No selling on iOS (App Store 3.1.1)

- `PacksAPI` has no `CreateBundleCheckout`, and nothing in the app builds that
  request. Do not add it.
- `PackSummary` does not carry `priceCents` or `currency`, so no screen can show a
  price by accident. Web's `priceLabel` was not ported.
- A locked pack shows "N more days in this pack" and the neutral line "Day
  one is free to read. The other days are part of the full pack." There is no
  price, no purchase button and no link out.
- A pack bought on web is unlocked here too: `GetBundle` reports it owned,
  `lockedDayCount` is 0, and "Open as my trip" works.

## Screens → RPCs

| Screen | RPC | Fields sent | Web source |
|---|---|---|---|
| Packs | `BundleService.ListBundles` | `theme`, `month`, `onlyFree` only when set (a present field is a filter), `pagination{page 1, pageSize 24}`; never `cityName` | `lib/api/bundles.ts` `usePacks` |
| Pack | `BundleService.GetBundle` | `slug` | `usePack` |
| Open as my trip | `BundleService.ClaimBundle` | `bundleId` (the pack's `id`, not its slug) | `useClaimPack` |
| (not on a screen yet) | `BundleService.ListMyBundles` | `pagination{1, 50}` (`PacksAPI.mine`) | `useMyPacks` |

The server (`internal/domain/bundle/handler.go`) serves `ListBundles` and
`GetBundle` without a token (`cmd/api/router.go` public procedures), and
still reads one when it is there, so the catalog reports `owned` with no second
call. `ClaimBundle` and `ListMyBundles` need a signed-in caller. The app
requires sign-in, so every call carries a token.

`GetBundle` returns only the days the caller may read: every day for a free
pack or an owned one, the free preview (day 1) otherwise, with the rest counted
in `lockedDayCount`. A free pack comes back with `owned = true`.

## Pure helpers (`Features/Packs/Model`)

| Helper | Web | Notes |
|---|---|---|
| `PackTheme` (label, emoji), `PackTheme.label(for:)` | `PACK_THEMES`, `PACK_THEME_META`, `themeLabel` | raw values are the server's seed ids (`local_life`); an unknown id shows as itself |
| `PackMonths.label` | `monthsLabel` | runs collapse to "Mar–May"; Nov/Dec/Jan/Feb reads "Nov–Feb"; `[]` "Any time"; all twelve "All year"; values outside 1…12 ignored |
| `PackMonths.upcoming(from:)` | `visibleMonths` | this month + next two, wrapping past December |
| `PackPoints.from` | `pointsFromDays` | only stops with a hydrated `poi` position; `seq` 1-based and contiguous across skips; `day` 0-based; id falls back to `"<dayNumber>-<index>"` |
| `PackDetail(_:)` | `toDetail` | stop `day = dayNumber - 1`, `blurb` = notes, `placeId` nil when empty, `timeToSpend` "N min" (none for 0 or unset), `lockedDayCount` → `access` |
| `PackSummary.badge` | `PackCard` | Free (free, even though the server says owned) / ✓ Yours (paid and owned) / lock (paid, not owned), never a price |
| `PackFilters.request` | `usePacks` | unset filters are left unset |

## How a pack reuses the result page

Pack stops become `Loci_Poi_POIDetailedInfo` (`PackStop.card`) so the page is
built from the Search result components: `ResultsMapCard` as the map hero (tap
→ `FullMapView` with the list in a sheet), `StopCard` rows, `PlaceDetailSheet`
on tap, and `DayGrouping.sequence` for the numbering. Days are grouped by the
server's 1-based `day_number`, so the pin colours and "Day N" labels match
web's.

- **Pins match cards.** The map is built from the same groups as the list, so
  card 3 is pin 3 even when an earlier stop has no position. (Web numbers pins
  with `seq`, which skips unplaced stops, so its map and list can disagree;
  `PackPoints.seq` is ported and tested, but it drives only the count under the
  map.)
- **Ids.** A card is keyed by the real POI id where it is unique in the pack,
  by the name when there is no POI (a pack stop's own id is a UUID too; used as
  a POI id it would fetch facts for, or save, the wrong thing), and by the
  stop's key for a second visit to the same place, so every row and pin stays
  unique. The detail sheet opened from the list always gets the real POI id
  (`PackStop.detailPlace`).
- **Time to spend** sits in the card's bottom-right corner; the day header adds
  the author's day title.
- "N of M stops have no position yet and are not on the map." appears under the
  map when `PackPoints` found fewer points than stops (web's copy).

## Access card

| `lockedDayCount` | Card |
|---|---|
| 0 | "Make it yours", web's copy, "Open as my trip" → `ClaimBundle` → push `TripEditorView(tripID:)`. While it runs: "Creating your trip…". On failure: "That did not save. Try again in a moment." |
| > 0 | Lock, "N more days in this pack", the neutral line above. Nothing to tap. |

The server copies the pack into a new trip on every `ClaimBundle` (it is not
idempotent). The screen remembers the trip it made, so a second tap reads "Open
my trip" and opens the same one instead of a duplicate. Leaving the page and
coming back can still make a second copy.

The AI line ("Written with AI assistance and checked by a person before
publishing. Opening hours and prices change — confirm before you go.") shows
when `isPaid`, as on web.

## States

Catalog: a skeleton of six redacted cards; a **real error state** ("Could not
load the City Packs" with the server's message and "Try again"; web shows the
empty copy when the API is down); two empty states (unfiltered: "No packs
published yet" / "They are written and checked by hand, so they arrive a few at
a time."; filtered: "No packs match those filters yet" with "Clear filters").
A refresh that fails with cards on screen is an alert, and the cards stay.

Pack: a redacted header, map and cards while loading; NotFound → "That pack is
not available" with "Browse the others" (back); any other failure → "Could not
load this pack" with "Try again". A failed refresh keeps the pack.

Filters are one theme and one month at a time (tap again to clear), plus
Free only and "Clear filters". Month chips are this month and the next two,
then "All months" shows all twelve. Unlike web, the filters are not in a URL.

## Analytics

`Analytics.screen("packs")`, `Analytics.screen("pack_detail", {slug})`,
`pack_viewed {slug}` on the first successful load, `pack_claimed {slug}` on a
successful claim. Web sends neither event yet.

## Tests and previews

`lociTests/PackDetailMappingTests.swift`: `PackPointsTests` (web's
`points.test.ts`, one to one, plus the carried fields), `PackThemesTests`
(web's `themes.test.ts` minus `priceLabel`, plus the server vocabulary,
non-adjacent runs and the month chips' wrap), `PackDetailMappingTests`
(`toDetail`: `day = dayNumber - 1`, ids, `timeToSpend`, access, the unplaced
count, pins numbered like cards, card ids for repeat visits and POI-less stops)
and `PackCatalogTests` (badge, size label, the request's unset fields).

Previews (Debug, offline through `PreviewPacksService`, which runs sample
protos through the real mapping): `-designPreview packs`, `packDetail` (free,
three days, one unplaced stop), `packLocked` (paid, day one, "2 more days").

## Server gaps

- `ClaimBundle` is not idempotent: every call inserts a new trip. iOS guards
  within one screen only. A server-side "one claim per user per pack" (or
  returning the existing trip) would fix it for both clients.
- `ClaimBundle` answers FailedPrecondition "this pack is not for sale" when the
  service was built without a trips repository (`s.trips == nil`), which reads
  wrong for a free pack. Both show "That did not save" here.
- Pack stops carry no images, so every card shows the hashed gradient.

## Not verified

Nothing here has run against the live API: the catalog (production had 0
published packs on 2026-09-22), claiming a free pack and landing in its trip,
a locked pack's preview, and a pack owned through web purchase opening
unlocked.
