# Loci iOS roadmap

Study guide to the codebase (layers, networking, search state, screens, tests): [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Phase 1 — Core MVP (this pass)
API and journey parity with web in a native shell. Slices and their notes:

| # | Slice | Note | PR |
|---|---|---|---|
| 1 | Shell, tokens, transport | `01-shell.md` | #1 |
| 2 | Auth refresh, Keychain | `02-auth.md` | #1 |
| 3 | Settings incl. MCP | `03-settings.md` | #2 |
| 6 | Streaming search, notifications, Ask Loci | `06-search.md`, `../ios-search-notifications.md` | #3 |
| 4 | Discover | `04-discover.md` | #4 |
| 5 | Near me | `05-nearby.md` | #4 |
| 7 | Trips editor | `07-trips.md` | #4 |
| 8 | Compare | `08-compare.md` | #4 |
| 9 | Saved | `09-saved.md` | #4 |

Decisions: local notifications only (no device-token RPC exists; "no new endpoints" wins); the current five tabs stay; Billing is not in the app.

Done when a device build can sign in, search, stream, map, edit a trip and resume from a notification. **Not yet verified against the live API** — nothing has been run signed-in.

## Server work that unlocks Phase 2 (not iOS UI)
- Device-token RPC + APNs sender on COMPLETE/ERROR. Owned by session loci-3a (web + server push). Tentative contract: payload keys `sessionId`, `cityName`, `domain`; one register RPC with a platform enum, `APNS` reserved. The iOS notification `userInfo` already uses those keys.
- StreamChat resume bugs, also loci-3a: replay does not follow a live generation; several events share one `event_id`; the resume buffer is per pod.
- Buf Swift + Connect-Swift generation in proto CI (today `gen/swift` is committed by hand).
- StoreKit 2 receipt validation + App Store Server Notifications.
- Sign in with Apple token validation.

## Phase 2 — iOS-native superpowers
1. ~~APNs search-complete + Universal Links (associated domain on lociai.fyi)~~ — done in `13-push-and-universal-links.md` (Phase 2A: proto v5.25.0, api #77, client #70, infra #190).
2. ~~Offline: cache for trips, stops and saved places; `BGAppRefreshTask` for weather, FX and alerts before a trip day.~~ — done in `14-offline-trip-day.md` (Phase 2B; serialized protos on disk, not SwiftData; read-only).
3. ~~Live Activities / Dynamic Island for an active trip day: current stop, time left, next stop.~~ — done in `14-offline-trip-day.md` (Phase 2B; schedule-driven, you start it; "closes in 45m" needs opening hours on the stop and is not there yet).
4. Widgets: next stop, destination GoScore, trip countdown.
5. Voice: mic → `SpeechService.Transcribe` → user confirms the text → StreamChat.
6. StoreKit 2 / Pro, if not already done.
7. System integrations: Apple Maps "Navigate", Wallet `.pkpass`, Handoff.
8. Place Intelligence / Field Kit: proximity prompts near a POI (hours right? noisy now?), badges if the proto supports it.

## Phase 1.5 — Parity pass 2 (Recents, Lists, Packs, Reviews, Contribute, Globe, trip extras)
Web's signed-in pages that have no iOS screen. Five tabs stay; Profile becomes the "You" hub, Packs enter from Discover, Lists is also a Saved segment. One PR per phase.

| # | Phase | Note | PR |
|---|---|---|---|
| 0 | You hub, Saved Lists segment, City Packs entry, `AppLink` deep links | `14-you-hub-and-app-links.md` | #28 |
| 1 | Recents (feed, cities, day buckets) | `15-recents.md` | #30 |
| 2 | Lists (list detail, add to list, entitlement sheet); blocked on server gaps, see the note | `16-lists.md` | this PR |
| 3 | Trip extras: server-synced checklists (proto + api), preferences, export, add to trip | | |
| 4 | City Packs (browse, detail, claim; no purchase on iOS) | `18-city-packs.md` | #33 |
| 5 | Reviews, place-centric: place section, write/edit sheet, See all, My reviews (server api #90 first) | `19-reviews.md` | this PR |
| 6 | Contribute (claims, opening hours, pending and missing places) | | |
| 7 | Globe / Where you've been | | |
| 8 | Web fixes, incl. AASA paths for the Phase 0 links | | |

## Phase 3 — Ecosystem (after Phase 2 is in daily use)
- watchOS: today's checklist, haptic "approaching next stop", complications.
- Siri / App Intents: "What's next on my Loci itinerary?", "Ask Loci for a quiet coffee nearby."
- Field utilities: offline FX from `GetFxRates`, drive cost from `EstimateDriveCost`.
- macOS: same account and trips, Handoff, desktop planning — a separate target.
- Onboarding wizard and Fastlane beta/prod lanes (Phase 1.5 if TestFlight is needed sooner).
