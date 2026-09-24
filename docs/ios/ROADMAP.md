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
2. Offline: SwiftData cache for trips, stops and saved places; `BGAppRefreshTask` for weather, FX and alerts before a trip day.
3. Live Activities / Dynamic Island for an active trip day: current stop, time left, next stop, "closes in 45m".
4. Widgets: next stop, destination GoScore, trip countdown.
5. Voice: mic → `SpeechService.Transcribe` → user confirms the text → StreamChat.
6. StoreKit 2 / Pro, if not already done.
7. System integrations: Apple Maps "Navigate", Wallet `.pkpass`, Handoff.
8. Place Intelligence / Field Kit: proximity prompts near a POI (hours right? noisy now?), badges if the proto supports it.

## Phase 3 — Ecosystem (after Phase 2 is in daily use)
- watchOS: today's checklist, haptic "approaching next stop", complications.
- Siri / App Intents: "What's next on my Loci itinerary?", "Ask Loci for a quiet coffee nearby."
- Field utilities: offline FX from `GetFxRates`, drive cost from `EstimateDriveCost`.
- macOS: same account and trips, Handoff, desktop planning — a separate target.
- Onboarding wizard and Fastlane beta/prod lanes (Phase 1.5 if TestFlight is needed sooner).
