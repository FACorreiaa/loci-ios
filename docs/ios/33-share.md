# 33 — Share by link (pass 3, Phase 1)

Places, saved itineraries and lists share a server-minted link instead of
text only; `lociai.fyi/share/<code>` opens in the app. Trips keep their own
sharing from the social layer (`TripShareMenu`, `/t/<code>`).

## RPCs

- `ShareService.CreateShareLink{user_id, content_type, content_id, title}` →
  `{share_code, share_url}` — web: `lib/api/share.ts createShareLink`.
- `ShareService.GetSharedContent{share_code}` → `SharedContent` (metadata +
  one of poi / hotel / restaurant / itinerary / list, summary fields only).
- `ItineraryService.GetItinerary{itinerary_id}` to open a shared itinerary.

## Pieces

- `Core/Share/ShareTarget.swift` — what is shared; `contentType` (hotels →
  HOTEL, restaurants → RESTAURANT, activities → ACTIVITY, else POI; itinerary;
  list), `fallbackText` (today's text share), `canLink` (stored ids only).
  `ShareLinks.share(code:)` builds `https://lociai.fyi/share/<code>`.
- `Core/Share/ShareAPI.swift` — the calls.
- `Core/Share/ShareSheetItem.swift` — minted when the screen appears, not on
  tap, so `ShareLink` never waits; a failed mint leaves the text and is not
  retried on every redraw. One `share_link_created{content_type}` per mint.
- `Features/Share/UI/SharedContentView.swift` — the summary card and an
  "Open the …" button: list → `ListDetailView(listID:)`, itinerary →
  `GetItinerary` → `SavedItineraryView`, place → `GetPOI` → `PlaceDetailSheet`.
  `shared_content_opened{content_type}`.
- `AppLink.shared(code:)` for `/share/<code>` on `lociai.fyi`, `loci://share/<code>`
  and, only for that path, `api.lociai.fyi`; routes to the Discover tab.
- Call sites: `PlaceDetailView` menu, `SavedItineraryView` toolbar,
  `ListDetailView` toolbar (new).

## Known gap — server base URL

The API mints `share_url` as `BASE_URL/share/<code>` with
`BASE_URL = https://api.lociai.fyi` (infra `apps/loci/data/config.yaml`), and
its OG page refreshes to `BASE_URL/<type>/<id>`, which is not a web page. So a
link pasted into Safari lands on the API host. Universal Links need the AASA
on the link's host; the app therefore accepts `api.lociai.fyi/share/…` by
parsing only — the system will not hand it to the app until either the web
gets a `/share/[code]` route plus the AASA path (plan Phase 9) and the server's
share base URL moves to `https://lociai.fyi`, or the API serves an AASA. Until
then the link works from inside the app (paste into Ask Loci, or any in-app
tap) and as a plain web preview.

## Previews

`-designPreview sharedPlace | sharedList | sharedItinerary`.
