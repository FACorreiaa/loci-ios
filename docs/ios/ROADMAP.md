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
| 2 | Lists (list detail, add to list, entitlement sheet); server gaps fixed in api #95 | `16-lists.md` | #32 |
| 3a | Trip checklists on the server (proto v5.27.0 + api) | server repos | live |
| 3b | Trip page parity: hero, preferences, export gate, synced checklists (offline via #29's cache) | `17-trip-extras.md` | #31 |
| 3c | Add to trip from place detail (fresh-version AddStop with one retry, day by number, create a trip), Edit trip banner on results | `22-add-to-trip.md` | #38 |
| 4 | City Packs (browse, detail, claim; no purchase on iOS) | `18-city-packs.md` | #33 |
| 5 | Reviews, place-centric: place section, write/edit sheet, See all, My reviews (server api #90 first) | `19-reviews.md` | #34 |
| 6 | Contribute: field reports (vocabulary, opening-hours editor), pending places, missing-place search, add a place, Report a fact on place detail | `20-contribute.md` | #35 |
| 6b | First-run profile wizard: budget, pace, getting around, interests → one default travel profile, offered once after sign-in (web: /trip-setup) | `31-first-run-profile.md` | this PR |
| 7 | Globe / Where you've been (MapKit globe, great-circle legs, stats, legs sheet, city → Recents) | `21-globe.md` | this PR |
| 8 | Web fixes, incl. AASA paths for the Phase 0 links (reviews rebuild + trip setup still to do) | loci-client | loci-client #78 |

## Phase 1.6 — Parity pass 3 (the RPCs iOS still never calls)
Plan: [`docs/superpowers/plans/2026-09-25-ios-parity-pass3.md`](../superpowers/plans/2026-09-25-ios-parity-pass3.md). Audit of 2026-09-25: 238 RPCs in the proto, 136 called from iOS `main`, 102 not (PRs #31, #35, #36 close trip extras, Contribute and Globe). One PR per phase; 2, 3, 6 and 8 can run in parallel.

| # | Phase | RPCs | Note | PR |
|---|---|---|---|---|
| 0 | Entitlements store (read-only plan; no paywall) | `entitlement.GetEntitlements` | `22-entitlements.md` | |
| 1 | Share by link: trips, lists, places; open `lociai.fyi/share/<code>` | `share.*` | `23-share.md` | |
| 2 | Recents recording from this phone + frequent places | `recents.RecordInteraction`, `GetCityInteractions`, `GetFrequentPlaces` | `24-recents-recording.md` | |
| 3 | GoScore on Discover, drive cost per leg | `localcontext.GetGoScore`, `EstimateDriveCost` | `25-goscore.md` | |
| 4 | PDF exports for results pages and lists | `export.*` | `26-exports.md` | |
| 5 | Lists completion: public lists, save/unsave, per-type views, item edits | `list.*` (10) | `27-lists-complete.md` | |
| 6 | Per-domain preferences in Travel profiles | `profile.*` (6) | `28-domain-preferences.md` | |
| 7 | Chat continuation in the Muse thread (probe `ContinueChat` first; fallback = re-stream) | `chat.ContinueChat` | `29-chat-continuation.md` | |
| 8 | Auth edges: change email, reset password by link (`ValidateSession` not needed) | `auth.*` (3) | `30-auth-edges.md` | |
| 9 | Web: AASA paths for share, confirm-email, reset-password | — | loci-client | |

Web-only by design, never on iOS: `payment.*` and `bundle.CreateBundleCheckout` (Stripe; iOS must use StoreKit), `statistics.*`, `ai_poi.*`, `custom_auth.getOauthURL/oauthCallback`, API keys / MCP.

### How to re-run the RPC audit
From `~/Work/production/apps/Loci`, with `loci-connect-proto` and `loci-ios` fetched:

```sh
python3 - <<'PY'
import subprocess,re,collections
proto="loci-connect-proto"; ios="loci-ios"
files=[f for f in subprocess.run(["git","-C",proto,"ls-tree","-r","--name-only","origin/main"],capture_output=True,text=True).stdout.split() if f.endswith(".connect.swift")]
src=subprocess.run(["git","-C",ios,"grep","-h","-o",r"\.[a-zA-Z0-9_]*(request","origin/main","--","loci/loci"],capture_output=True,text=True).stdout
used=set(re.findall(r"\.([a-zA-Z0-9_]+)\(request",src))
tot=u=0
for f in files:
    body=subprocess.run(["git","-C",proto,"show",f"origin/main:{f}"],capture_output=True,text=True).stdout
    ms=sorted(set(re.findall(r"func `([a-zA-Z0-9_]+)`\(request",body)))
    miss=[m for m in ms if m not in used]; tot+=len(ms); u+=len(ms)-len(miss)
    if miss: print(f.split("/")[-1].replace(".connect.swift",""), f"{len(ms)-len(miss)}/{len(ms)}:", ", ".join(miss))
print(f"rpcs={tot} used={u} unused={tot-u}")
PY
```

## Deferred — Pro gating (documented 2026-09-25, not scheduled)
Decision: **the app stays open, and nothing is gated by plan anywhere.** The gates that existed (Day-1 exports, Markdown, list and place caps, compare candidates, Trip Kit's first day) were switched off on 2026-09-25 behind one flag per repo, left in place for later: `PLAN_GATING` on the server (`subscription.Entitled`), `PLAN_GATING_ENABLED` on web (`canUsePro`), `PlanGating.enabled` on iOS (`ProGate.entitled`, `TripExportGate.decide(gating:)`). Flip all three together to start gating; the tests for the gated behaviour pass `gating: true` explicitly and keep it honest meanwhile. Nothing on iOS is paywalled until (a) Stripe has taken one real charge on web and (b) StoreKit 2 has completed one sandbox purchase with server-side receipt validation (see *Server work that unlocks Phase 2*). Phase 1.6/0 only reads the plan so gates stop hard-coding `isPro = false`.

When gating starts, in this order (each is a small PR on top of `EntitlementsStore`):
1. **Multi-day exports and the offline trip day for the whole trip.** Free keeps Day 1, the same rule web already applies (`TripExportGate`, `entitlements.export_full`). Offline is what a traveller pays for at the airport.
2. **Multi-city trips:** free = 2 cities, Pro = 5 (`MAX_STOPS` on web; the server enforces).
3. **Trip-day Live Activity and reminders** as Pro. Cheap to gate, visible every day of a trip.
4. **City Packs claim** on Pro (already coded; 0 packs live at the time of writing).

Rules that hold whatever is gated: neutral copy ("included with Pro"), no link to web pricing (App Store 3.1.1), the `x-loci-entitlement` refusal path stays the source of truth for counts, and every gate reads `EntitlementsStore.shared.current.isPro` — never a second flag.

Not gated, ever: user-submitted places and place facts (contributions are the supply side; reward contributors instead of charging them).

## Phase 3 — Ecosystem (after Phase 2 is in daily use)
- watchOS: today's checklist, haptic "approaching next stop", complications.
- Siri / App Intents: "What's next on my Loci itinerary?", "Ask Loci for a quiet coffee nearby."
- Field utilities: offline FX from `GetFxRates`, drive cost from `EstimateDriveCost`.
- macOS: same account and trips, Handoff, desktop planning — a separate target.
- Onboarding wizard and Fastlane beta/prod lanes (Phase 1.5 if TestFlight is needed sooner).

## Phase 4 — Social (after share-by-link is in daily use)
The first viral loop is a trip a friend can open. It is built from what the server already has, in this order:
1. **Share by link** — pass 3, Phase 1 (`share.CreateShareLink`, `GetSharedContent`; `lociai.fyi/share/<code>` opens in the app).
2. **Friends on Loci, by invite.** A share link that also invites: the recipient who signs up becomes a "friend", and both see each other's *shared trips* (not positions) on Saved and on the globe ("Where you've been" gains a "Friends" layer). Needs new server work: a `friends` table, invite acceptance, and a per-trip "share with friends" toggle. No social-network sign-in is involved: Facebook's `user_friends` only returns friends who also installed the app, and X's follower APIs are paid and rate-limited, so neither gives a usable graph at our scale.
3. **Trip comments and reactions** on a shared trip, once 2 has users.

### Parked idea — friends' live location on the map/globe (owner's idea, 2026-09-25)
Show where the people you follow / your friends are, on the map or globe, possibly via X or Facebook auth. Parked, not rejected: it needs its own product before any code — opt-in per trip, an expiry, a kill switch, a privacy policy update and App Store review scrutiny — and a friend graph that exists first (Phase 4/2). Revisit when Phase 4/2 has real friends in it; the honest interim is "friends' *trips* on the map", which Phase 4/2 delivers.
