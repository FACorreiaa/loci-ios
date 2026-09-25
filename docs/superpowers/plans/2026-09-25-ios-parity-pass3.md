# iOS parity pass 3 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each phase below is one PR; when a phase is picked up, expand it into bite-sized RED→GREEN steps in a ledger the way pass 2 did (`.superpowers/sdd/<plan>/progress.md`).

**Goal:** Close the remaining gap between the iOS app and the web app's signed-in surface, so every server RPC a traveller can reach on the web is reachable on iOS, and the app can later gate Pro features without new plumbing.

**Architecture:** One `nonisolated enum XAPI` per feature wrapping the generated Connect-Swift clients through `rpc(fallback, request) { … }`; `@MainActor @Observable` stores with injected protocol services for previews and tests; pure logic in `nonisolated` helpers with Swift Testing suites ported from the web's own tests. No new tabs: Share, Exports and Chat continuation attach to existing screens; Lists, Preferences and Auth edges extend existing feature folders; Entitlements is a `Core/` singleton every gate reads.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Observation, Swift Testing, Connect-Swift (`LociConnectProto` from `../loci-connect-proto/gen/swift`), PostHog wrapper (`Core/Analytics/Analytics.swift`), Universal Links (`Core/Routing/AppRouter.swift`).

**Spec:** this file's *Context* section, derived from the RPC coverage audit of 2026-09-25 (238 RPCs in the proto, 136 called by iOS `main`, 102 not; open PRs #31, #35, #36 cover trip extras, Contribute and Globe). Web is the behavioural reference for each phase and is cited per phase.

## Global Constraints

- **The app stays open.** No paywall, no StoreKit, no purchase screen in this pass. Pro gating is documented in `docs/ios/ROADMAP.md` under *Deferred — Pro gating* and is not built here. Phase 0 only *reads* the plan so existing gates stop hard-coding `isPro = false`.
- **App Store 3.1.1:** iOS never links to web pricing or `CreateBundleCheckout`/`payment.*`. Copy on a locked feature stays neutral ("included with Pro"), as `TripExportGate` already does.
- **No new RPCs, no proto changes.** Everything here exists in `loci-connect-proto` main and `gen/swift`. Verify each RPC is implemented on the server with an unauthenticated probe first (protovalidate runs before auth, so a `400 invalid_argument` proves the route exists and a `501 unimplemented` proves it does not — the saved-detail lesson).
- **Reuse:** `PlaceDetailView`, `StopCard`, `DaySection`, `ResultsMapCard`, `PlacePicker`, `TripExportGate` (PR #31), `EntitlementLimit`, `AppLink`, `SessionLink`, `ShareText`. Do not rebuild any of them.
- **Conventions from pass 2 apply unchanged:** worktree per phase (`loci-ios-<slug>`), stage explicitly (another session commits in the same checkouts), `./scripts/format.sh --skip-install --lint-only`, `fastlane test` or `build-for-testing`, a `-designPreview <case>` per new screen, a `docs/ios/NN-<slug>.md` note, a ROADMAP row, an ARCHITECTURE touch-up, PostHog event names mirrored from web.
- **Universal Links:** every new deep link added to `AppLink` needs the matching path in web's `public/.well-known/apple-app-site-association` (Phase 9 ships the web half; until then the link works from Safari's banner only).
- **Proto pinning:** iOS builds the proto repo's default-branch HEAD unpinned. Never merge an iOS PR while proto main is mid-change.

## Review Focus

1. **Entitlements fetch fails or returns `plan = ""`** → every gate must fall back to *free* and never crash or lock a free feature; pinned by `EntitlementsTests.unknownPlanIsFree` (Phase 0).
2. **Share link for content the server has not persisted yet** (a streamed itinerary before its bookmark row exists) → `CreateShareLink` returns `success = false`; the sheet must fall back to the text share, not show an empty link; pinned by `ShareTargetTests.fallsBackToTextWhenNoContentId` (Phase 1).
3. **`RecordInteraction` on a metered connection during a stream** → must be fire-and-forget, never awaited on the main path, never retried in a loop; pinned by `InteractionRecorderTests.dropsWhenOffline` (Phase 2).
4. **A free account exporting a multi-day itinerary PDF** → locked with the neutral notice, no server call; pinned by `TripExportGate` tests (PR #31) reused for `ItineraryPDFExport` (Phase 4).
5. **`ContinueChat` answering `requires_clarification = true` with no `updated_itinerary`** → the thread shows the question and keeps the current result, never blanks the page; pinned by `ContinueChatReducerTests.clarificationKeepsResult` (Phase 7).

---

## Context

The RPC audit (proto `main` vs iOS `main`, 2026-09-25):

| Service | iOS uses | Missing on iOS |
|---|---|---|
| `share` | 0/3 | `createShareLink`, `getShareMetadata`, `getSharedContent` |
| `chat` | 8/15 | `continueChat`, `bookmarkPoi`/`removeBookmark`, `getSessionPois`, `startChat`, `endSession`, `getRunStatus` |
| `export` | 1/6 | `exportPoisToPdf`, `exportHotelsToPdf`, `exportRestaurantsToPdf`, `exportActivitiesToPdf`, `exportListToPdf` |
| `list` | 7/17 | `searchPublicLists`, `savePublicList`, `unsaveList`, `getSavedLists`, `getListItems`, `getListHotels`, `getListRestaurants`, `getListItineraries`, `createItinerary`, `updateListItem` |
| `profile` | 5/11 | `getDiningPreferences`, `getAccommodationPreferences`, `getActivityPreferences`, `getItineraryPreferences`, `getCombinedFilters`, `getUserPreferenceProfile` |
| `recents` | 2/5 | `recordInteraction`, `getCityInteractions`, `getFrequentPlaces` |
| `localcontext` | 5/7 | `getGoScore`, `estimateDriveCost` |
| `auth` | 15/19 | `changeEmail`, `confirmEmailChange`, `resetPassword`, `validateSession` |
| `entitlement` | 0/1 | `getEntitlements` |

Web-only by design, **not** in this plan: `payment.*` (Stripe; iOS must use StoreKit), `bundle.createBundleCheckout`, `statistics.*` (admin), `ai_poi.*` (health), `custom_auth.getOauthURL/oauthCallback` (iOS signs in natively), `apikey`/MCP surfaces.

Existing iOS pieces each phase builds on: `Features/Lists/Model/EntitlementLimit.swift` (reads the `x-loci-entitlement` header on a refused write), `TripExportGate` and `TripExportSection` (PR #31), `Features/Search/UI/Results/PlaceDetailSheet.swift` (`ShareLink(item: shareText)` — text only today), `Features/Recents/Services/RecentsAPI.swift` (reads only), `Features/Settings/UI/TravelProfilesView.swift` + `TravelProfileEditor.swift` (search profiles, no per-domain preferences), `Features/Chat/MuseThread.swift` (history + standing tasks; no follow-up composer), `Features/Auth/Services/AuthService.swift` (`login`, `register`, `verifyMFA`, `forgotPassword`, `logout`), `Core/Routing/AppRouter.swift` (`AppLink` cases `list`, `pack`, `trip`, `recents`, `contribute`; `SessionLink` for results).

## Phase order and why

| # | Phase | Depends on | PR |
|---|---|---|---|
| 0 | Entitlements store (read-only Pro state) | — | |
| 1 | Share by link (itinerary, list, place) + open shared links | 0 (nothing gated, but the Pro badge and share sheet land on the same screens) | |
| 2 | Recents recording | — | |
| 3 | GoScore and drive cost on Discover | — | |
| 4 | PDF exports for results pages and lists | 0 (uses `Entitlements.isPro` in `TripExportGate`) | |
| 5 | Lists completion (public lists, save/unsave, per-type views, item edits) | 0 (limits), 1 (share a list) | |
| 6 | Per-domain preferences in Travel profiles | — | |
| 7 | Chat continuation in the Muse thread | server probe first | |
| 8 | Auth edges (change email, reset password by link) | — | |
| 9 | Web fixes: AASA paths for share, confirm-email and reset-password links | 1, 8 | |

Phases 2, 3, 6 and 8 are independent of each other and can run in parallel worktrees. Phases 1, 4 and 5 want Phase 0 merged first.

---

## Phase 0: Entitlements store

**Web reference:** `lib/api/entitlements.ts` (`fetchEntitlements`, `Entitlements{plan, listsUsed, listsLimit, placesSaved, placesLimit, advancedFilters, exportFull}`), `components/EntitlementsBadge.tsx`.

**RPC:** `EntitlementService.GetEntitlements(GetEntitlementsRequest{}) -> Entitlements{plan, lists_used, lists_limit (5 free, -1 Pro), places_saved, places_limit (50 free, -1 Pro), advanced_filters, export_full}`.

**Files:**
- Create: `Core/Entitlements/Entitlements.swift` — `nonisolated struct Entitlements: Equatable, Sendable` mirroring the proto with `static let free`, `var isPro: Bool { plan == "pro" }`, `init(_ proto: Loci_Entitlement_V1_Entitlements)`.
- Create: `Core/Entitlements/EntitlementsAPI.swift` — `nonisolated enum EntitlementsAPI { static func fetch() async throws -> Entitlements }` via `rpc("Could not load your plan.", request) { await client.getEntitlements(request: $0, headers: [:]) }`.
- Create: `Core/Entitlements/EntitlementsStore.swift` — `@MainActor @Observable final class EntitlementsStore { static let shared; private(set) var current: Entitlements = .free; private(set) var loaded: Loaded<Entitlements>; func refresh() async; func invalidate() }` using `cacheThrough` (`Core/Cache/Loaded.swift`) with key `entitlements/<userId>` so a cold launch shows the last known plan. Refresh on `authSessionDidAuthenticate`, on foreground, and after any `EntitlementLimit` refusal. Clear on `authSessionDidInvalidate`.
- Modify: `Features/Trips/Model/TripExportGate.swift` call sites (PR #31) — pass `EntitlementsStore.shared.current.isPro` instead of a constant.
- Modify: `Features/Lists/Model/EntitlementLimit.swift` — on a refusal, call `EntitlementsStore.shared.invalidate()` so the counts refresh.
- Modify: `Features/Profile/UI/YouSection.swift` — a plan chip ("Free · 3/5 lists · 12/50 places" or "Pro"), no upgrade button (app stays open).
- Test: `loci/lociTests/EntitlementsTests.swift`.

**Interfaces:**
- Produces: `EntitlementsStore.shared.current: Entitlements`, `Entitlements.isPro`, `Entitlements.listsRemaining: Int?`, `Entitlements.placesRemaining: Int?` (nil when unlimited).

- [ ] **Step 1: Failing tests** — `Entitlements(proto)` maps every field; `Entitlements.free` has `plan == "free"`, limits 5 and 50; `unknownPlanIsFree` (plan `""` and `"enterprise"` are not Pro); `remaining` is nil at `-1`.
- [ ] **Step 2: Run** `xcodebuild test … -only-testing:lociTests/EntitlementsTests` → FAIL, type missing.
- [ ] **Step 3: Implement** `Entitlements`, `EntitlementsAPI`, `EntitlementsStore`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Wire** the refresh triggers in `lociApp.swift` next to the push registration hooks; wire `TripExportGate`, `EntitlementLimit`, `YouSection`.
- [ ] **Step 6: Design preview** `-designPreview youHubPro` and `youHubFree`.
- [ ] **Step 7: Docs** `docs/ios/22-entitlements.md`; ROADMAP row; commit `feat(ios): read the account's plan and limits`.

---

## Phase 1: Share by link

**Web reference:** `lib/api/share.ts` (`createShareLink(contentType, contentId, title, description?, imageUrl?)` → `{shareCode, shareUrl}`), `components/ui/ShareModal.tsx`, `components/ShareMenu.tsx`, `lib/share.ts`, route `share/[code]`.

**RPCs:**
- `ShareService.CreateShareLink(CreateShareLinkRequest{user_id, content_type: ShareContentType (POI=1, HOTEL=2, RESTAURANT=3, ITINERARY=4, LIST=5, ACTIVITY=6), content_id, title, description ≤500, image_url ≤2048}) -> {success, message, share_code, share_url}`.
- `ShareService.GetSharedContent(GetSharedContentRequest{share_code}) -> {success, message, content: SharedContent}` — read the `SharedContent` oneof in `gen/swift/loci/share/share.pb.swift` before building the viewer.
- `ShareService.GetShareMetadata(share_code)` — web uses it for OG tags; iOS uses it only as the lightweight first fetch for the link preview row.

**Files:**
- Create: `Core/Share/ShareTarget.swift` — `nonisolated enum ShareTarget { case place(id:, name:, kind: ShareKind), itinerary(id:, title:), list(id:, title:) }` with `var contentType: Loci_Share_ShareContentType`, `var fallbackText: String` (today's `shareText`), and `static func resolve(...)` helpers.
- Create: `Core/Share/ShareAPI.swift` — `createLink(userId:, target:) async throws -> URL`, `sharedContent(code:) async throws -> Loci_Share_SharedContent`.
- Create: `Core/Share/ShareSheetItem.swift` — an `@Observable` model that starts with the text and swaps in the URL once created, so `ShareLink` never waits on the network (Review Focus 2).
- Create: `Features/Share/UI/SharedContentView.swift` — opens `lociai.fyi/share/<code>`: itinerary → reuse the results day list (`DaySection`/`StopCard`), list → reuse `ListDetailView`, place → `PlaceDetailView`. Read-only, with "Save a copy" where the underlying RPC exists (`SaveItinerary`, `SavePublicList` — Phase 5 — , `AddToFavorites`).
- Modify: `Core/Routing/AppRouter.swift` — `AppLink.shared(code: String)` for `("share", 2)`; `Tab` mapping → `.discover`.
- Modify: `PlaceDetailSheet.swift:176`, the trip page share (`TripHero`/`TripExportSection` from #31), `ListDetailView`'s toolbar — replace text-only `ShareLink` with `ShareSheetItem`.
- Test: `loci/lociTests/ShareTargetTests.swift` (content type mapping, fallback text, `fallsBackToTextWhenNoContentId`), `AppLinkTests` gains the `share` case.
- Analytics: `share_link_created{content_type}` and `shared_content_opened{content_type}`.

- [ ] Server probe: `curl -s -X POST https://api.lociai.fyi/loci.share.ShareService/GetSharedContent -H 'Content-Type: application/json' -d '{}'` → expect `400`, not `501`.
- [ ] Failing tests → implement `ShareTarget`, `ShareAPI`, `ShareSheetItem` → pass.
- [ ] `SharedContentView` + `AppLink.shared` + previews `sharedItinerary`, `sharedList`, `sharedPlace`.
- [ ] Replace the three `ShareLink` call sites.
- [ ] Docs `docs/ios/23-share.md`; ROADMAP; commit `feat(ios): share trips, lists and places by link`.

---

## Phase 2: Recents recording

**Web reference:** web records through the server side of each write today (searches, favourites, saves); the explicit `RecordInteraction` call is what gives the Recents feed device-side events (place viewed, chat opened, recommendation tapped). Types: `InteractionType {SEARCH=1, VIEW=2, FAVORITE=3, UNFAVORITE=4, SAVE_ITINERARY=5, CREATE_LIST=6, CHAT=7, DISCOVERY=8, RECOMMENDATION_CLICK=9, BOOKING_ATTEMPT=10}`.

**RPC:** `RecentsService.RecordInteraction(RecordInteractionRequest{user_id, interaction_type, entity_id, entity_type, entity_name, city_id, context: InteractionContext{source_page, user_agent, device_type: "ios", location?, session_id, referrer, custom_properties}, metadata}) -> {success, interaction_id, message}`. Also wire the two reads iOS skips: `GetCityInteractions` (for `RecentCityView`'s Interactions tab, currently fed only by the global history) and `GetFrequentPlaces` (a "Places you keep coming back to" row on Recents).

**Files:**
- Create: `Core/Recents/InteractionRecorder.swift` — `@MainActor @Observable final class InteractionRecorder { static let shared; func record(_ type: Loci_Recents_InteractionType, entity: (id: String, type: String, name: String), cityId: String?, source: String, sessionId: String? = nil) }` — enqueues onto a detached task, drops on `APIError.network`, never retries, never throws to the caller (Review Focus 3). One call site per event, no sprinkling: `SearchSessionController.start` (SEARCH), `PlaceDetailSheet.onAppear` (VIEW), `FavoriteButton` (FAVORITE/UNFAVORITE), the itinerary Save (SAVE_ITINERARY), `ListsStore.create` (CREATE_LIST), `MuseThread` open (CHAT), Discover card tap (DISCOVERY), In-season/Here-brief card tap (RECOMMENDATION_CLICK).
- Modify: `Features/Recents/Services/RecentsAPI.swift` — add `record(…)`, `cityInteractions(userId:cityId:)`, `frequentPlaces(userId:)`.
- Modify: `Features/Recents/UI/RecentsView.swift` — a "Frequent places" horizontal row above the feed when non-empty.
- Test: `loci/lociTests/InteractionRecorderTests.swift` with a fake service: builds the request with `device_type == "ios"` and the app version in `user_agent`; `dropsWhenOffline`; never blocks the caller (measure with a `Clock`).

- [ ] Probe `RecordInteraction` → 400 expected.
- [ ] Failing tests → recorder → pass → call sites → docs `docs/ios/24-recents-recording.md` → commit `feat(ios): record what the traveller does so Recents shows this phone too`.

---

## Phase 3: GoScore and drive cost on Discover

**Web reference:** `components/ui/GoScoreCard.tsx` (score, verdict, factors, summary, `hasEstimatedInputs` note), used by `compare/ColumnCard.tsx`; Discover's here-brief is the natural iOS home (`Features/Discover`, PR #11 "where the traveller is standing").

**RPCs:**
- `LocalContextService.GetGoScore(GetGoScoreRequest{city_name?, latitude?, longitude?, origin_lat?, origin_lon?, start?, end?}) -> {score: GoScore{score, verdict, factors: [ScoreFactor], summary ≤300, has_estimated_inputs}, city_name}`.
- `LocalContextService.EstimateDriveCost(EstimateDriveCostRequest{distance_km, currency?}) -> {estimate: DriveCostEstimate}`.

**Files:**
- Create: `Features/Discover/Model/GoScoreModel.swift` — `nonisolated struct GoScoreModel` with `tone` (web's verdict → colour mapping), `factorRows`, `estimatedNote`.
- Create: `Features/Discover/UI/GoScoreCard.swift` — compact card in the here-brief; tap expands factors.
- Create: `Features/Trips/UI/DriveCostRow.swift` — on a trip whose legs have `distance_km` (multi-city, #27), a "≈ €42 fuel" row per leg using `EstimateDriveCost`, currency from the profile.
- Modify: `Features/Discover/Services/LocalContextAPI.swift` (or wherever `localcontext` calls live today — `git grep -n localcontext` first) — add `goScore(...)`, `driveCost(km:currency:)`.
- Test: `loci/lociTests/GoScoreModelTests.swift` (verdict tones, estimated note, empty factors).

- [ ] Probe both RPCs → 400.
- [ ] Failing tests → model → pass → cards → previews `goScoreGood`, `goScoreMaybe`, `driveCost` → docs `docs/ios/25-goscore.md` → commit.

---

## Phase 4: PDF exports for results pages and lists

**Web reference:** `lib/api/export.ts` (`exportPOIsToPDF(items, title?)`, `exportHotelsToPDF`, `exportRestaurantsToPDF`, `exportActivitiesToPDF`, `exportItineraryToPDF`, `exportListToPDF`), `lib/utils/pdf-export.ts`, `components/trip/TripExportMenu.tsx`.

**RPCs:** `ExportService.ExportPOIsToPDF(ExportPOIsRequest) / ExportHotelsToPDF / ExportRestaurantsToPDF / ExportActivitiesToPDF / ExportItineraryToPDF / ExportListToPDF → ExportPDFResponse` — read the request messages in `gen/swift/loci/export/export.pb.swift` for the exact selection shape (web sends a `SelectionItem[]` built from the visible cards). `ExportPDFResponse` carries the bytes or a URL; check which and handle both.

**Gate:** results-page PDFs (hotels, restaurants, activities, POIs) and list PDFs are free on web; the itinerary PDF follows `TripExportGate` (Day 1 free, multi-day Pro). Reuse `TripExportGate.decide(.pdf, isPro:, dayCount:)` from PR #31 with `EntitlementsStore.shared.current.isPro` (Phase 0).

**Files:**
- Create: `Core/Export/PDFExport.swift` — `nonisolated enum PDFExport { static func poisRequest(_ stops: [Loci_Poi_POIDetailedInfo], title:) -> Loci_Export_ExportPOIsRequest … }` plus `static func file(from: Loci_Export_ExportPDFResponse, name:) throws -> URL` writing to `FileManager.temporaryDirectory` for `ShareLink(item: url)`.
- Create: `Core/Export/ExportAPI.swift` — one static func per RPC.
- Create: `Features/Search/UI/Results/ResultsExportButton.swift` — toolbar item on hotels/restaurants/activities/itinerary result pages; shows a progress overlay, then the share sheet.
- Modify: `ListDetailView` toolbar (Phase 5 touches the same file: land Phase 4 first or rebase).
- Test: `loci/lociTests/PDFExportTests.swift` — request builders keep order and day numbers; `file(from:)` names the file after the city and date; itinerary export uses `TripExportGate` (locked → no request built).
- Analytics: `trip_exported{format:"pdf", surface}` mirroring web.

- [ ] Probe `ExportPOIsToPDF` → 400.
- [ ] Failing tests → builders → pass → buttons → previews → docs `docs/ios/26-exports.md` → commit.

---

## Phase 5: Lists completion

**Web reference:** `routes/lists/index.tsx`, `routes/lists/[id].tsx`, `lib/api/lists.ts`, `lib/lists/list-detail.ts`, `components/lists/AddToListButton.tsx`. Note web's own gaps found in pass 2 (`/lists/[id]` 404, `AddToListButton` dead code) — do not port those.

**RPCs:**
- `SearchPublicLists(SearchPublicListsRequest{query, city_id, categories[], limit, offset, sort_by}) -> {lists: [ListWithItems], total_count, metadata}`.
- `SavePublicList{user_id, list_id}`, `UnsaveList{user_id, list_id}`, `GetSavedLists{user_id, limit, offset}`.
- `GetListItems{user_id, list_id, include_content_details} -> {items: [ListItemWithContent], total_count}`; `GetListHotels`, `GetListRestaurants`, `GetListItineraries` (same shape per type).
- `CreateItinerary` (turn a list into an itinerary list) and `UpdateListItem{user_id, list_id, item_id, content_type, position, notes ≤4000, day_number, time_slot, …}`.

**Files:**
- Modify: `Features/Lists/Services/ListsAPI.swift` — add the ten wrappers, keeping the `listRPC` helper that preserves the `x-loci-entitlement` header.
- Create: `Features/Lists/Model/PublicListsQuery.swift` (`nonisolated struct` for query/city/categories/sort with `Equatable` for cache keys) and `Features/Lists/Model/ListItemEdit.swift` (notes, day, time slot → `UpdateListItemRequest`).
- Create: `Features/Lists/UI/PublicListsView.swift` — search field, city chip, sort; rows reuse `ListRow`; "Save" toggles `SavePublicList`/`UnsaveList`.
- Create: `Features/Lists/UI/SavedListsSection.swift` — the "Saved from others" segment under Saved → Lists.
- Modify: `Features/Lists/UI/ListDetailView.swift` — type tabs (Places / Hotels / Restaurants / Itineraries) backed by the per-type RPCs; item sheet with notes, day number, time slot (`ListItemEdit`); "Make an itinerary" (`CreateItinerary`) when the list has ≥ 2 places; Share (Phase 1); Export (Phase 4).
- Modify: `EntitlementLimit` refusal → `EntitlementsStore.invalidate()` (Phase 0) and the existing entitlement sheet.
- Test: `loci/lociTests/ListPayloadTests.swift` extended (public query, item edit, day/time round trip), `PublicListsQueryTests`.
- Analytics: `list_saved{public:true}`, `list_item_edited`.

- [ ] Probe `SearchPublicLists` and `UpdateListItem` → 400 each.
- [ ] Failing tests → models → pass → views → previews `publicLists`, `listDetailTabs`, `listItemEdit` → docs `docs/ios/27-lists-complete.md` → commit.

---

## Phase 6: Per-domain preferences in Travel profiles

**Web reference:** `routes/profiles/index.tsx`, `components/features/Settings/TravelProfiles.tsx`, `lib/api/profiles.ts` (`useAccommodationPreferences`, `useDiningPreferences`, `useActivityPreferences`, `useItineraryPreferences`, `useCombinedFilters`, and the matching update mutations).

**RPCs:** `ProfileService.GetDiningPreferences(GetDomainPreferencesRequest{profile_id}) -> {success, message, preferences: DiningPreferences}` and the same for Accommodation, Activity, Itinerary; `GetCombinedFilters{profile_id, domain?}`; `GetUserPreferenceProfile{profile_id}`. Update RPCs: whichever `Update*Preferences` exist in `profile.proto` (check `gen/swift/loci/profile/profile.connect.swift`; web's mutations name them).

**Files:**
- Modify: `Features/Settings/UI/TravelProfileEditor.swift` — four disclosure sections (Dining, Stay, Activities, Itinerary) fed by the per-domain RPCs, saved through their update RPCs; a read-only "Applied filters" footer from `GetCombinedFilters`.
- Create: `Features/Settings/Model/DomainPreferences.swift` — `nonisolated` value types mirroring the four protos with `Equatable` diffing so Save only sends changed domains.
- Modify: `Features/Settings/Services/SettingsClients.swift` (or a new `ProfilePreferencesAPI.swift`) — one static func per RPC.
- Test: `loci/lociTests/DomainPreferencesTests.swift` — proto ↔ model round trips per domain; unchanged domains are not sent.

- [ ] Probe the four getters → 400.
- [ ] Failing tests → models → pass → editor sections → preview `travelProfileDomains` → docs `docs/ios/28-domain-preferences.md` → commit.

---

## Phase 7: Chat continuation in the Muse thread

**Web reference:** web does **not** call `ContinueChat` today (it re-streams `StreamChat` with `session_id` for refinements). The contract exists: `ChatService.ContinueChat(ContinueChatRequest{session_id, message, city_name?, context_type: DomainType}) -> ChatResponse{session_id, message, updated_itinerary?: AiCityResponse, is_new_session, requires_clarification, suggested_actions[]}`. This phase is worth doing only if the server implements it — probe first; if it answers `501`, replace this phase with "refine by re-streaming `StreamChat` with `session_id`", which the iOS `ChatStreamClient` already supports.

**Files (ContinueChat path):**
- Create: `Features/Chat/Model/ContinueChatReducer.swift` — `nonisolated enum` folding a `ChatResponse` into the thread: appends the assistant message, replaces the result when `updated_itinerary` is set, shows `suggested_actions` as chips, keeps the result on `requires_clarification` (Review Focus 5).
- Create: `Features/Chat/Services/ContinueChatService.swift` — protocol + live impl through `rpc`.
- Modify: `Features/Chat/MuseThread.swift` and its view — a composer at the bottom of a finished result ("Make day 2 lighter", "Swap the museum for a park"); chips call the composer with the suggestion.
- Modify: `SearchSessionController` — when the reducer replaces the result, write it through the same `store.saveResult` path so offline copies and the trip-day cache stay coherent.
- Test: `loci/lociTests/ContinueChatReducerTests.swift`.
- Analytics: `chat_continued{domain}`.

- [ ] Probe `ContinueChat` → 400 (build) or 501 (fallback plan).
- [ ] Failing tests → reducer → pass → composer + chips → preview `museFollowUp` → docs `docs/ios/29-chat-continuation.md` → commit.

---

## Phase 8: Auth edges

**Web reference:** `components/features/Auth/ResetPassword.tsx` (token from the email link, `ResetPassword{token, new_password}`), the account email change in Settings (`ChangeEmail{password, new_email}` then `ConfirmEmailChange{token}` from the link).

**RPCs:** `AuthService.ChangeEmail`, `ConfirmEmailChange`, `ResetPassword` (`ForgotPassword` already wired). `ValidateSession` is **not** needed on iOS: `JWTTokenInspector` already answers "who am I" locally, and web only calls it as a race workaround.

**Files:**
- Modify: `Features/Auth/Services/AuthService.swift` — `changeEmail(password:newEmail:)`, `confirmEmailChange(token:)`, `resetPassword(token:newPassword:)`.
- Create: `Features/Settings/UI/ChangeEmailView.swift` — password + new email, then a "check your inbox" state.
- Create: `Features/Auth/UI/ResetPasswordView.swift` — opened from the link, new password twice, then sign in.
- Modify: `Core/Routing/AppRouter.swift` — `AppLink.resetPassword(token:)` for `("reset-password", 1)` with `?token=`, `AppLink.confirmEmail(token:)` for `("confirm-email", 1)`; both are allowed while signed out (today every `AppLink` assumes a session — add the signed-out branch in `lociApp.swift` next to the login screen).
- Test: `AppLinkTests` (tokens parsed, signed-out allowed), `loci/lociTests/AuthEdgesTests.swift` (request shapes; password mismatch never calls the server).

- [ ] Probe the three RPCs → 400.
- [ ] Failing tests → service → pass → views → previews `changeEmail`, `resetPassword` → docs `docs/ios/30-auth-edges.md` → commit.

---

## Phase 9: Web fixes for the new links

**Repo:** `loci-client`.

- Modify: `public/.well-known/apple-app-site-association` — add `{"/":"/share/*"}`, `{"/":"/reset-password*"}`, `{"/":"/confirm-email*"}` to `components`.
- Verify the three web routes exist and read the same query parameter names iOS parses (`code` in the path for share; `token` for the two auth links); align iOS to web if they differ, never the other way round (web's emails are already sent).
- Deploy, then `curl -sI https://lociai.fyi/.well-known/apple-app-site-association` → `200 application/json`, and the live-bundle grep for `api.lociai.fyi` (the Workers Builds race).
- Apple's CDN caches AASA for up to a day; test links on a fresh install after that.

---

## Verification (whole pass)

- Every phase: `./scripts/format.sh --skip-install --lint-only` clean; `xcodebuild test -project loci.xcodeproj -scheme "loci Beta" -destination 'platform=iOS Simulator,id=07B6F787-28AC-4EB2-AFE2-30D577C05A0B' -only-testing:lociTests -quiet CODE_SIGNING_ALLOWED=NO` green; one `-designPreview` screenshot per new screen attached to the PR.
- After the last phase, re-run the RPC audit script (see `docs/ios/ROADMAP.md` → *How to re-run the RPC audit*) and expect the "missing on iOS" list to contain only the web-only services named in *Context*.
- Device QA per phase on TestFlight, signed in, against the live API: the pass-2 lesson is that nothing counts as done until it has been run with a real token.

## Self-review notes

- Spec coverage: the nine gaps from the audit each map to a phase (Share→1, Chat→7, Exports→4, Lists→5, Preferences→6, Recents→2, Local context→3, Auth→8, Entitlements→0); the web half of the links is Phase 9.
- Placeholders: none; where a proto shape must be read at build time (`SharedContent` oneof, `Export*Request` selection, `Update*Preferences` names) the plan says which generated file to open rather than guessing a field.
- Type consistency: `EntitlementsStore.shared.current.isPro` is the one Pro source; `TripExportGate.decide(_:isPro:dayCount:)` keeps PR #31's signature; `AppLink` gains `shared(code:)`, `resetPassword(token:)`, `confirmEmail(token:)`.
