# Offline Trip Day Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trips, saved places, weather and money stay readable with no signal, and a trip day runs as a Live Activity driven by the day's schedule.

**Architecture:** A `LocalCache` actor stores serialized protos on disk and every loader becomes cache-through (render the copy, fetch, overwrite; on a network error keep the copy and say so). A pure `DayTimeline` turns a `TripDay` into timed slots; `TripDayActivityController` projects the timeline onto an ActivityKit activity drawn by the existing `NearbyWalkWidget` extension. A second `BGAppRefreshTask` prefetches the next trip day.

**Tech Stack:** Swift 6 (default MainActor isolation), SwiftUI, SwiftProtobuf (`serializedData` / `init(serializedBytes:)`), ActivityKit (`@preconcurrency import`), BackgroundTasks, CoreLocation (`POIProximityMonitor`), Swift Testing, SwiftLint via `scripts/format.sh --skip-install --lint-only`.

**Spec:** `docs/superpowers/specs/2026-09-24-offline-trip-day-design.md`

## Global Constraints

- Read-only cache: no offline edits, no queue. Editor edit controls disable in the stale state with footer text "Connect to edit".
- Files under `Application Support/loci/cache/<kind>/<id>.bin`, written atomically with `.completeFileProtectionUntilFirstUserAuthentication` (the `SearchStore` pattern).
- Only `APIError.network` counts as offline; any other error with a cached copy also renders the copy (`.stale`), without one renders the error.
- Cache chip copy: "Saved <relative time>" and "Offline · last updated <relative time>".
- Background task id `com.fernandocorreia.loci.trip-prefetch`, listed in `loci/Info.plist` `BGTaskSchedulerPermittedIdentifiers`.
- Timing defaults from `CalendarSchedule`: 09:00 start, 90 min per stop, 15 min buffer, clamp 30–240 min.
- One trip-day activity at a time; auto-end 30 min after the last slot or 12 h after start.
- New shared types live in `loci/loci/Shared/` and must be added to BOTH the `loci` and `NearbyWalkWidget` targets in `project.pbxproj` (that folder is not a synchronized folder).
- Every new type outside a View is `nonisolated` (value types) or `@MainActor` (observable classes); tests touching app types use `@MainActor struct`.
- No new dependencies, no new endpoints, no new targets.
- Stage files explicitly; never `git add -A`. Lint must report 0 violations before each commit.

## Review Focus

1. A trip whose `TripDay.date` is midnight UTC on a phone west of UTC: `DayTimeline.today` must compare calendar days in the phone's time zone, not instants. Test in Task 6.
2. A trip day with stops that all lack coordinates: the activity must run on the schedule with no fences and nil distances, not fail to start. Test in Task 9.
3. Token expiry while offline (`APIError.unauthorized`) with a cached trip: the page must render the copy as stale, not sign the user out or blank the page. Test in Task 2.
4. Reopening the app after the last slot has ended: `refresh` must end the activity, not show a negative countdown. Test in Task 9.
5. Two trip days on the same date (a multi-city draft): `today` returns the first non-travel day; the band shows one day. Test in Task 6.

---

### Task 1: LocalCache

**Files:**
- Create: `loci/loci/Core/Cache/LocalCache.swift`
- Test: `loci/lociTests/LocalCacheTests.swift`

**Interfaces:**
- Produces: `actor LocalCache { init(root: URL? = nil); enum Kind: String { case trip, trips, saved, localContext, fx }; func put<M: SwiftProtobuf.Message>(_ message: M, kind: Kind, id: String) throws; func get<M: SwiftProtobuf.Message>(_ type: M.Type, kind: Kind, id: String) -> Cached<M>?; func ids(kind: Kind) -> [String]; func remove(kind: Kind, id: String); func clear() }`, `struct Cached<M: Sendable>: Sendable { let value: M; let fetchedAt: Date }`, `static let shared = LocalCache()`, `static func key(latitude: Double, longitude: Double) -> String` ("%.3f,%.3f").

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import LociConnectProto
import Testing

@testable import loci

struct LocalCacheTests {
  private func temporaryCache() -> LocalCache {
    LocalCache(root: FileManager.default.temporaryDirectory.appending(path: "loci-cache-\(UUID().uuidString)"))
  }

  @Test func roundTripsAProtoWithItsFetchTime() async throws {
    let cache = temporaryCache()
    var trip = Loci_Trip_TripDraft()
    trip.id = "t1"
    trip.title = "Rome on foot"
    try await cache.put(trip, kind: .trip, id: "t1")
    let cached = try #require(await cache.get(Loci_Trip_TripDraft.self, kind: .trip, id: "t1"))
    #expect(cached.value.title == "Rome on foot")
    #expect(abs(cached.fetchedAt.timeIntervalSinceNow) < 5)
    #expect(await cache.ids(kind: .trip) == ["t1"])
  }

  @Test func missingAndRemovedEntriesReadAsNil() async throws {
    let cache = temporaryCache()
    #expect(await cache.get(Loci_Trip_TripDraft.self, kind: .trip, id: "nope") == nil)
    try await cache.put(Loci_Trip_TripDraft(), kind: .trip, id: "t2")
    await cache.remove(kind: .trip, id: "t2")
    #expect(await cache.get(Loci_Trip_TripDraft.self, kind: .trip, id: "t2") == nil)
    #expect(await cache.ids(kind: .trip).isEmpty)
  }

  @Test func clearEmptiesEveryKind() async throws {
    let cache = temporaryCache()
    try await cache.put(Loci_Trip_TripDraft(), kind: .trip, id: "a")
    try await cache.put(Loci_Localcontext_LocalContext(), kind: .localContext, id: LocalCache.key(latitude: 41.9028, longitude: 12.4964))
    await cache.clear()
    #expect(await cache.ids(kind: .trip).isEmpty)
    #expect(await cache.ids(kind: .localContext).isEmpty)
  }

  @Test func coordinateKeyRoundsToThreeDecimals() {
    #expect(LocalCache.key(latitude: 41.90284, longitude: 12.49637) == "41.903,12.496")
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd loci && xcodebuild test -project loci.xcodeproj -scheme "loci Beta" -destination 'platform=iOS Simulator,id=07B6F787-28AC-4EB2-AFE2-30D577C05A0B' -only-testing:lociTests/LocalCacheTests -quiet CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:" | head`
Expected: `cannot find 'LocalCache' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import SwiftProtobuf

/// Serialized protos on disk, one file per entry, so trips, saved places and
/// the day's forecast stay readable with no signal. Disposable: everything
/// here can be fetched again, so there is no schema and nothing to migrate.
/// Same storage rules as SearchStore: atomic writes, readable after the first
/// unlock so a background refresh can use it.
actor LocalCache {
  enum Kind: String, CaseIterable, Sendable { case trip, trips, saved, localContext, fx }

  static let shared = LocalCache()

  private let root: URL
  private var indexes: [Kind: [String: Date]] = [:]

  init(root: URL? = nil) {
    self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "loci/cache")
  }

  /// "41.903,12.496": the key for anything fetched for a coordinate.
  nonisolated static func key(latitude: Double, longitude: Double) -> String {
    String(format: "%.3f,%.3f", latitude, longitude)
  }

  func put<M: SwiftProtobuf.Message>(_ message: M, kind: Kind, id: String) throws {
    let dir = directory(kind)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try message.serializedData().write(to: file(kind, id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    var index = loadIndex(kind)
    index[id] = Date()
    saveIndex(kind, index)
  }

  func get<M: SwiftProtobuf.Message>(_ type: M.Type, kind: Kind, id: String) -> Cached<M>? {
    guard let fetchedAt = loadIndex(kind)[id], let data = try? Data(contentsOf: file(kind, id)),
      let value = try? M(serializedBytes: data)
    else { return nil }
    return Cached(value: value, fetchedAt: fetchedAt)
  }

  func ids(kind: Kind) -> [String] { loadIndex(kind).keys.sorted() }

  func remove(kind: Kind, id: String) {
    try? FileManager.default.removeItem(at: file(kind, id))
    var index = loadIndex(kind)
    index[id] = nil
    saveIndex(kind, index)
  }

  func clear() {
    try? FileManager.default.removeItem(at: root)
    indexes = [:]
  }

  // MARK: - Files

  private func directory(_ kind: Kind) -> URL { root.appending(path: kind.rawValue) }
  private func file(_ kind: Kind, _ id: String) -> URL {
    directory(kind).appending(path: id.replacingOccurrences(of: "/", with: "_") + ".bin")
  }
  private func indexURL(_ kind: Kind) -> URL { directory(kind).appending(path: "index.json") }

  private func loadIndex(_ kind: Kind) -> [String: Date] {
    if let cached = indexes[kind] { return cached }
    let decoded = (try? Data(contentsOf: indexURL(kind))).flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
    indexes[kind] = decoded
    return decoded
  }

  private func saveIndex(_ kind: Kind, _ index: [String: Date]) {
    indexes[kind] = index
    try? FileManager.default.createDirectory(at: directory(kind), withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(index) {
      try? data.write(to: indexURL(kind), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
  }
}

/// A cached value and when the server last gave it to us.
nonisolated struct Cached<M: Sendable>: Sendable {
  let value: M
  let fetchedAt: Date
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Same command as Step 2. Expected: 4 passed. Then `./scripts/format.sh --skip-install --lint-only` → 0 violations.

- [ ] **Step 5: Commit**

```bash
git add loci/loci/Core/Cache/LocalCache.swift loci/lociTests/LocalCacheTests.swift
git commit -m "Add LocalCache: serialized protos on disk with a fetch-time index"
```

---

### Task 2: Cache-through loading helper

**Files:**
- Create: `loci/loci/Core/Cache/CacheThrough.swift`
- Test: `loci/lociTests/CacheThroughTests.swift`

**Interfaces:**
- Consumes: `LocalCache`, `Cached`, `APIError`.
- Produces: `enum Loaded<M: Sendable>: Sendable { case fresh(M), stale(M, since: Date, reason: APIError), missing(APIError) }` with `var value: M?`, `var staleSince: Date?`, `var isOffline: Bool`; `func cacheThrough<M: SwiftProtobuf.Message>(_ type: M.Type, kind: LocalCache.Kind, id: String, cache: LocalCache = .shared, onCached: ((Cached<M>) -> Void)? = nil, fetch: () async throws -> M) async -> Loaded<M>`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import LociConnectProto
import Testing

@testable import loci

struct CacheThroughTests {
  private func cache() -> LocalCache {
    LocalCache(root: FileManager.default.temporaryDirectory.appending(path: "loci-ct-\(UUID().uuidString)"))
  }
  private func trip(_ title: String) -> Loci_Trip_TripDraft {
    var t = Loci_Trip_TripDraft()
    t.id = "t1"
    t.title = title
    return t
  }

  @Test func freshFetchOverwritesTheCopy() async throws {
    let cache = cache()
    try await cache.put(trip("old"), kind: .trip, id: "t1")
    let loaded = await cacheThrough(Loci_Trip_TripDraft.self, kind: .trip, id: "t1", cache: cache) { trip("new") }
    guard case .fresh(let value) = loaded else { return Issue.record("expected fresh") }
    #expect(value.title == "new")
    #expect(try #require(await cache.get(Loci_Trip_TripDraft.self, kind: .trip, id: "t1")).value.title == "new")
  }

  @Test func networkErrorKeepsTheCopyAsStale() async throws {
    let cache = cache()
    try await cache.put(trip("copy"), kind: .trip, id: "t1")
    var handedCopy: String?
    let loaded = await cacheThrough(Loci_Trip_TripDraft.self, kind: .trip, id: "t1", cache: cache, onCached: { handedCopy = $0.value.title }) {
      throw APIError.network("offline")
    }
    #expect(handedCopy == "copy")
    guard case .stale(let value, _, let reason) = loaded else { return Issue.record("expected stale") }
    #expect(value.title == "copy")
    #expect(loaded.isOffline)
    if case .network = reason {} else { Issue.record("reason should be the network error") }
  }

  @Test func expiredTokenWithACopyIsStaleNotMissing() async throws {
    let cache = cache()
    try await cache.put(trip("copy"), kind: .trip, id: "t1")
    let loaded = await cacheThrough(Loci_Trip_TripDraft.self, kind: .trip, id: "t1", cache: cache) { throw APIError.unauthorized(nil) }
    #expect(loaded.value?.title == "copy")
    #expect(!loaded.isOffline)
  }

  @Test func noCopyAndAnErrorIsMissing() async {
    let loaded = await cacheThrough(Loci_Trip_TripDraft.self, kind: .trip, id: "t1", cache: cache()) { throw APIError.network("offline") }
    guard case .missing = loaded else { return Issue.record("expected missing") }
    #expect(loaded.value == nil)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the Task 1 command with `-only-testing:lociTests/CacheThroughTests`. Expected: `cannot find 'cacheThrough' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import SwiftProtobuf

/// What a cache-through load produced: the server's answer, the phone's copy
/// because the server could not be reached, or nothing.
nonisolated enum Loaded<M: Sendable>: Sendable {
  case fresh(M)
  case stale(M, since: Date, reason: APIError)
  case missing(APIError)

  var value: M? {
    switch self {
    case .fresh(let value), .stale(let value, _, _): value
    case .missing: nil
    }
  }

  var staleSince: Date? {
    if case .stale(_, let since, _) = self { return since }
    return nil
  }

  /// True only for a network failure: the "Offline" wording, as opposed to
  /// a server error while connected, which keeps the "Saved" wording.
  var isOffline: Bool {
    if case .stale(_, _, .network) = self { return true }
    if case .missing(.network) = self { return true }
    return false
  }
}

/// Render the copy first (`onCached`), then fetch. Success overwrites the
/// copy; a failure keeps it. `APIError.network` is the only "offline" reason;
/// any other failure with a copy still shows the copy so an expired token
/// does not blank a page the phone could draw.
nonisolated func cacheThrough<M: SwiftProtobuf.Message & Sendable>(
  _ type: M.Type,
  kind: LocalCache.Kind,
  id: String,
  cache: LocalCache = .shared,
  onCached: (@MainActor (Cached<M>) -> Void)? = nil,
  fetch: () async throws -> M
) async -> Loaded<M> {
  let copy = await cache.get(type, kind: kind, id: id)
  if let copy, let onCached { await onCached(copy) }
  do {
    let value = try await fetch()
    try? await cache.put(value, kind: kind, id: id)
    return .fresh(value)
  } catch {
    let reason = (error as? APIError) ?? .custom(error.localizedDescription)
    if let copy { return .stale(copy.value, since: copy.fetchedAt, reason: reason) }
    return .missing(reason)
  }
}
```

Note: `Loci_*` messages are `Sendable` in the generated code, so the `& Sendable` bound holds.

- [ ] **Step 4: Run the tests to verify they pass**

Expected: 4 passed, lint clean.

- [ ] **Step 5: Commit**

```bash
git add loci/loci/Core/Cache/CacheThrough.swift loci/lociTests/CacheThroughTests.swift
git commit -m "Add cacheThrough: render the copy, fetch, keep the copy on failure"
```

---

### Task 3: Cache chip and the Trips list

**Files:**
- Create: `loci/loci/Core/Cache/CacheChip.swift`
- Modify: `loci/loci/Features/Trips/UI/TripsView.swift` (`load()` at ~41–50, list header)

**Interfaces:**
- Consumes: `cacheThrough`, `Loaded`.
- Produces: `struct CacheChip: View { init(loaded: Loaded<some Sendable>?) }` rendering "Saved 2h ago" / "Offline · last updated 2h ago" / nothing when fresh; `enum CacheChipText { static func text(staleSince: Date?, isOffline: Bool, now: Date = Date()) -> String? }` (pure, tested).

- [ ] **Step 1: Write the failing test** (append to `loci/lociTests/CacheThroughTests.swift`)

```swift
  @Test func chipWordingFollowsTheState() {
    let now = Date()
    let twoHoursAgo = now.addingTimeInterval(-7200)
    #expect(CacheChipText.text(staleSince: nil, isOffline: false, now: now) == nil)
    #expect(CacheChipText.text(staleSince: twoHoursAgo, isOffline: false, now: now) == "Saved 2 hours ago")
    #expect(CacheChipText.text(staleSince: twoHoursAgo, isOffline: true, now: now) == "Offline · last updated 2 hours ago")
  }
```

- [ ] **Step 2: Run it to verify it fails** (`cannot find 'CacheChipText'`).

- [ ] **Step 3: Write the chip**

```swift
import SwiftUI

/// The one line a page shows when it is drawing the phone's copy.
nonisolated enum CacheChipText {
  static func text(staleSince: Date?, isOffline: Bool, now: Date = Date()) -> String? {
    guard let staleSince else { return nil }
    let relative = RelativeDateTimeFormatter()
    relative.unitsStyle = .full
    let ago = relative.localizedString(for: staleSince, relativeTo: now)
    return isOffline ? "Offline · last updated \(ago)" : "Saved \(ago)"
  }
}

struct CacheChip<M: Sendable>: View {
  let loaded: Loaded<M>?

  var body: some View {
    if let loaded, let text = CacheChipText.text(staleSince: loaded.staleSince, isOffline: loaded.isOffline) {
      Label(text, systemImage: loaded.isOffline ? "wifi.slash" : "internaldrive")
        .lociCoordStyle(10)
        .accessibilityLabel(text)
    }
  }
}
```

- [ ] **Step 4: Make the Trips list cache-through**

In `TripsView`, add `@State private var loaded: Loaded<Loci_Trip_ListTripsResponse>?` and replace `load()`:

```swift
  private func load() async {
    isLoading = trips.isEmpty
    var request = Loci_Trip_ListTripsRequest()
    request.pagination.page = 1
    request.pagination.pageSize = 50
    let sent = request
    loaded = await cacheThrough(Loci_Trip_ListTripsResponse.self, kind: .trips, id: "all", onCached: { trips = $0.value.trips }) {
      try await rpc("Could not load your trips.", sent) { await TripAPI.client.listTrips(request: $0, headers: [:]) }
    }
    if let value = loaded?.value { trips = value.trips } else if case .missing(let reason) = loaded { error = reason.userMessage }
    isLoading = false
  }
```

(Keep the request the file already builds; only the `rpc` call moves inside `fetch`.) Put `CacheChip(loaded: loaded)` as the first row of the list, inside a `Section` with no header, `.listRowBackground(Color.clear)`.

- [ ] **Step 5: Build, run the tests, lint** (full `lociTests`). Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add loci/loci/Core/Cache/CacheChip.swift loci/loci/Features/Trips/UI/TripsView.swift loci/lociTests/CacheThroughTests.swift
git commit -m "Trips list reads the cached copy first and says when it is stale"
```

---

### Task 4: Trip editor cache-through with edits disabled offline

**Files:**
- Modify: `loci/loci/Features/Trips/UI/TripEditorView.swift` (`load()` ~161, toolbar ~50, `daySection` ~92–120, `apply(...)`)

**Interfaces:**
- Consumes: `cacheThrough`, `CacheChip`.
- Produces: `@State private var loaded: Loaded<Loci_Trip_TripDraft>?`, `private var canEdit: Bool` (true only when `loaded` is `.fresh` or nil-while-loading).

- [ ] **Step 1: Replace `load()`**

```swift
  private func load() async {
    var request = Loci_Trip_GetTripRequest()
    request.tripID = tripID
    let sent = request
    loaded = await cacheThrough(Loci_Trip_TripDraft.self, kind: .trip, id: tripID, onCached: { trip = $0.value }) {
      try await rpc("Could not load the trip.", sent) { await TripAPI.client.getTrip(request: $0, headers: [:]) }
    }
    if let value = loaded?.value { trip = value } else if case .missing(let reason) = loaded { error = reason.userMessage }
  }
```

Every successful edit already adopts the returned `TripDraft` through `apply(...)`; add one line there after adopting: `Task { try? await LocalCache.shared.put(draft, kind: .trip, id: tripID) }` so the copy follows edits.

- [ ] **Step 2: Disable edits in the stale state**

```swift
  private var canEdit: Bool {
    switch loaded {
    case .fresh, nil: true
    case .stale, .missing: false
    }
  }
```

- Toolbar: `Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }.disabled(!canEdit)`; when `canEdit` turns false set `isEditing = false` (`.onChange(of: canEdit) { _, ok in if !ok { isEditing = false } }`).
- `daySection` swipe actions and `.onMove`: wrap with `if canEdit` (`ForEach … .deleteDisabled(!canEdit).moveDisabled(!canEdit)` and the swipe action closures return nothing when `!canEdit`).
- Pace picker and the duration stepper in `StopRow`: `.disabled(!canEdit)`.
- Under the title, `CacheChip(loaded: loaded)`; when `!canEdit`, a `Section { } footer: { Text("Connect to edit") }` at the top.

- [ ] **Step 3: Build, run tests, lint.** Expected green (no new tests: the pure parts are covered in Task 2; the view has none, like the rest of the editor).

- [ ] **Step 4: Commit**

```bash
git add loci/loci/Features/Trips/UI/TripEditorView.swift
git commit -m "Trip editor draws the cached trip offline and disables edits until connected"
```

---

### Task 5: Saved hub and results side data

**Files:**
- Modify: `loci/loci/Features/Saved/UI/SavedView.swift` (`load`, `loadFavorites` ~104, `loadItineraries` ~112)
- Modify: `loci/loci/Features/Search/UI/Results/ResultsSideData.swift` (`loadContext` ~24–48)

- [ ] **Step 1: Saved lists through the cache**

```swift
  private func loadFavorites() async -> Loaded<Loci_Favorites_V1_GetFavoritesResponse> {
    await cacheThrough(Loci_Favorites_V1_GetFavoritesResponse.self, kind: .saved, id: "favorites", onCached: { favorites = $0.value.favorites }) {
      try await rpc("Could not load saved places.", favoritesRequest) { await SavedAPI.favorites.getFavorites(request: $0, headers: [:]) }
    }
  }
```

Same shape for itineraries with id `"itineraries"` and `Loci_Itinerary_GetUserItinerariesResponse` (use the response type the file already unwraps; keep the existing request builders as `private var favoritesRequest` / `itinerariesRequest`). `load()` awaits both, assigns `favorites`/`itineraries` from `.value`, sets `error` only when both are `.missing`, and keeps `@State private var loadedFavorites: Loaded<…>?` for `CacheChip(loaded: loadedFavorites)` under the segment picker.

- [ ] **Step 2: Side data through the cache**

Replace the two static dictionaries in `ResultsSideData` with the cache:

```swift
  func loadContext(latitude: Double, longitude: Double) async {
    let key = LocalCache.key(latitude: latitude, longitude: longitude)
    guard !Self.isOffline else { contextChecked = true; return }
    async let context = cacheThrough(Loci_Localcontext_LocalContext.self, kind: .localContext, id: key, onCached: { self.localContext = $0.value }) {
      try await ResultsAPI.localContext(latitude: latitude, longitude: longitude)
    }
    async let fx = cacheThrough(Loci_Localcontext_GetFxRatesResponse.self, kind: .fx, id: key, onCached: { self.fxRates = $0.value.rates }) {
      try await ResultsAPI.fxRates(latitude: latitude, longitude: longitude)
    }
    let (loadedContext, loadedFx) = await (context, fx)
    if let value = loadedContext.value { localContext = value }
    if let value = loadedFx.value { fxRates = value.rates }
    contextLoaded = loadedContext
    contextChecked = true
  }
```

Add `private(set) var contextLoaded: Loaded<Loci_Localcontext_LocalContext>?` and show `CacheChip(loaded: side.contextLoaded)` at the end of `LocalContextStrip`'s VStack in `ResultsPage` (pass it as a new optional parameter `chip: AnyView?` is over-engineering; instead render `CacheChip(loaded: side.contextLoaded)` directly under `LocalContextStrip(...)` in `ResultsPage.body`).

- [ ] **Step 3: Build, run tests, lint.** Expected green; `ResultsParityTests` unchanged.

- [ ] **Step 4: Commit**

```bash
git add loci/loci/Features/Saved/UI/SavedView.swift loci/loci/Features/Search/UI/Results/ResultsSideData.swift loci/loci/Features/Search/UI/Results/ResultsPage.swift
git commit -m "Saved lists and the day's forecast and money read from the cache first"
```

---

### Task 6: DayTimeline

**Files:**
- Create: `loci/loci/Features/Trips/Model/DayTimeline.swift`
- Test: `loci/lociTests/DayTimelineTests.swift`

**Interfaces:**
- Consumes: `CalendarSchedule` constants (`Features/Search/Model/DayGrouping.swift`), `Loci_Trip_TripDay`, `Loci_Trip_TripStop`, `Loci_Trip_TripLeg`, `Loci_Trip_TripDraft`.
- Produces: `nonisolated struct TimelineSlot: Equatable, Sendable { let stop: Loci_Trip_TripStop; let index: Int; let start: Date; let end: Date; let coordinate: CLLocationCoordinate2D?; let distanceToNextMeters: Double? }` (custom `==` on `stop.id`, `index`, `start`, `end`); `nonisolated enum DayTimeline { static func slots(day:legs:calendar:) -> [TimelineSlot]; static func today(in:now:calendar:) -> Loci_Trip_TripDay?; static func current(_:at:) -> TimelineSlot?; static func next(_:after:) -> TimelineSlot? }`.

- [ ] **Step 1: Write the failing tests**

```swift
import CoreLocation
import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

struct DayTimelineTests {
  private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }
  private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in cal: Calendar) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
  }
  private func stop(_ name: String, start: Int? = nil, minutes: Int? = nil, lat: Double? = nil, lon: Double? = nil) -> Loci_Trip_TripStop {
    var s = Loci_Trip_TripStop()
    s.id = name
    s.name = name
    if let start { s.startMinute = Int32(start) }
    if let minutes { s.durationMinutes = Int32(minutes) }
    if let lat, let lon {
      s.poi.latitude = lat
      s.poi.longitude = lon
    }
    return s
  }
  private func day(_ date: Date?, stops: [Loci_Trip_TripStop], travel: Bool = false, startMinute: Int? = nil) -> Loci_Trip_TripDay {
    var d = Loci_Trip_TripDay()
    d.id = UUID().uuidString
    if let date { d.date = Google_Protobuf_Timestamp(date: date) }
    d.stops = stops
    d.travelDay = travel
    if let startMinute { d.dayStartMinute = Int32(startMinute) }
    return d
  }

  @Test func defaultsStartAtNineWithNinetyMinuteSlotsAndBuffers() {
    let cal = utc
    let d = day(date(2026, 10, 8, in: cal), stops: [stop("A"), stop("B")])
    let slots = DayTimeline.slots(day: d, legs: [], calendar: cal)
    #expect(slots.map(\.index) == [0, 1])
    #expect(slots[0].start == date(2026, 10, 8, 9, 0, in: cal))
    #expect(slots[0].end == date(2026, 10, 8, 10, 30, in: cal))
    #expect(slots[1].start == date(2026, 10, 8, 10, 45, in: cal))
  }

  @Test func explicitStartAndDurationWinAndAreClamped() {
    let cal = utc
    let d = day(date(2026, 10, 8, in: cal), stops: [stop("A", start: 14 * 60, minutes: 10), stop("B", minutes: 600)])
    let slots = DayTimeline.slots(day: d, legs: [], calendar: cal)
    #expect(slots[0].start == date(2026, 10, 8, 14, 0, in: cal))
    #expect(slots[0].end == date(2026, 10, 8, 14, 30, in: cal))   // clamped up to 30
    #expect(slots[1].end.timeIntervalSince(slots[1].start) == 240 * 60)  // clamped down to 240
  }

  @Test func dayStartMinuteMovesTheFirstStop() {
    let cal = utc
    let d = day(date(2026, 10, 8, in: cal), stops: [stop("A")], startMinute: 10 * 60 + 30)
    #expect(DayTimeline.slots(day: d, legs: [], calendar: cal)[0].start == date(2026, 10, 8, 10, 30, in: cal))
  }

  @Test func distanceComesFromTheLegElseTheStraightLine() {
    let cal = utc
    var leg = Loci_Trip_TripLeg()
    leg.fromName = "A"
    leg.toName = "B"
    leg.distanceKm = 1.5
    let d = day(date(2026, 10, 8, in: cal), stops: [
      stop("A", lat: 41.9028, lon: 12.4964), stop("B", lat: 41.8902, lon: 12.4922), stop("C", lat: 41.8986, lon: 12.4769),
    ])
    let slots = DayTimeline.slots(day: d, legs: [leg], calendar: cal)
    #expect(slots[0].distanceToNextMeters == 1500)
    let straight = try! #require(slots[1].distanceToNextMeters)
    #expect(straight > 1400 && straight < 1700)
    #expect(slots[2].distanceToNextMeters == nil)
  }

  @Test func todayMatchesTheCalendarDayWestOfUTC() {
    var lisbon = Calendar(identifier: .gregorian)
    lisbon.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let midnightUTC = date(2026, 10, 8, in: utc)  // 17:00 the day before in Los Angeles
    var trip = Loci_Trip_TripDraft()
    trip.days = [day(midnightUTC, stops: [stop("A")])]
    let nowLA = lisbon.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 9))!
    #expect(DayTimeline.today(in: trip, now: nowLA, calendar: lisbon)?.id == trip.days[0].id)
  }

  @Test func todaySkipsTravelDaysAndTakesTheFirstOfTwo() {
    let cal = utc
    let d = date(2026, 10, 8, in: cal)
    var trip = Loci_Trip_TripDraft()
    let travel = day(d, stops: [], travel: true)
    let first = day(d, stops: [stop("A")])
    let second = day(d, stops: [stop("B")])
    trip.days = [travel, first, second]
    #expect(DayTimeline.today(in: trip, now: date(2026, 10, 8, 12, in: cal), calendar: cal)?.id == first.id)
    #expect(DayTimeline.today(in: trip, now: date(2026, 10, 9, 12, in: cal), calendar: cal) == nil)
  }

  @Test func currentAndNextFollowTheClock() {
    let cal = utc
    let d = day(date(2026, 10, 8, in: cal), stops: [stop("A"), stop("B")])
    let slots = DayTimeline.slots(day: d, legs: [], calendar: cal)
    #expect(DayTimeline.current(slots, at: date(2026, 10, 8, 8, in: cal)) == nil)
    #expect(DayTimeline.current(slots, at: date(2026, 10, 8, 9, 30, in: cal))?.index == 0)
    #expect(DayTimeline.current(slots, at: date(2026, 10, 8, 10, 40, in: cal))?.index == 0)  // in the buffer: still A
    #expect(DayTimeline.current(slots, at: date(2026, 10, 8, 13, in: cal))?.index == 1)     // after the last slot: last
    #expect(DayTimeline.next(slots, after: slots[0])?.index == 1)
    #expect(DayTimeline.next(slots, after: slots[1]) == nil)
  }
}
```

- [ ] **Step 2: Run to verify they fail** (`cannot find 'DayTimeline'`).

- [ ] **Step 3: Write the implementation**

```swift
import CoreLocation
import Foundation
import LociConnectProto
import SwiftProtobuf

/// One stop with the time it occupies on a trip day.
nonisolated struct TimelineSlot: Equatable, Sendable {
  let stop: Loci_Trip_TripStop
  let index: Int
  let start: Date
  let end: Date
  let coordinate: CLLocationCoordinate2D?
  let distanceToNextMeters: Double?

  static func == (lhs: TimelineSlot, rhs: TimelineSlot) -> Bool {
    lhs.stop.id == rhs.stop.id && lhs.index == rhs.index && lhs.start == rhs.start && lhs.end == rhs.end
  }
}

/// A trip day as a schedule. Stops with `start_minute` start then; the rest
/// follow the previous slot plus the buffer. Durations come from
/// `duration_minutes`, else the Trip Kit default, clamped like it.
nonisolated enum DayTimeline {
  static func slots(day: Loci_Trip_TripDay, legs: [Loci_Trip_TripLeg], calendar: Calendar = .current) -> [TimelineSlot] {
    guard day.hasDate else { return [] }
    let midnight = calendar.startOfDay(for: day.date.date)
    let dayStart = day.hasDayStartMinute ? Int(day.dayStartMinute) : CalendarSchedule.dayStartHour * 60
    var cursor = midnight.addingTimeInterval(TimeInterval(dayStart * 60))
    var slots: [TimelineSlot] = []
    for (index, stop) in day.stops.enumerated() {
      let start = stop.hasStartMinute ? midnight.addingTimeInterval(TimeInterval(Int(stop.startMinute) * 60)) : cursor
      let minutes = min(max(stop.hasDurationMinutes ? Int(stop.durationMinutes) : CalendarSchedule.defaultMinutes, CalendarSchedule.minMinutes), CalendarSchedule.maxMinutes)
      let end = start.addingTimeInterval(TimeInterval(minutes * 60))
      let next = index + 1 < day.stops.count ? day.stops[index + 1] : nil
      slots.append(TimelineSlot(
        stop: stop, index: index, start: start, end: end,
        coordinate: coordinate(of: stop),
        distanceToNextMeters: next.flatMap { distance(from: stop, to: $0, legs: legs) }
      ))
      cursor = end.addingTimeInterval(TimeInterval(CalendarSchedule.bufferMinutes * 60))
    }
    return slots
  }

  /// The first non-travel day dated today in the phone's calendar.
  static func today(in trip: Loci_Trip_TripDraft, now: Date = Date(), calendar: Calendar = .current) -> Loci_Trip_TripDay? {
    trip.days.first { $0.hasDate && !$0.travelDay && calendar.isDate($0.date.date, inSameDayAs: now) }
  }

  /// The slot containing `at`, else the latest one that has started.
  static func current(_ slots: [TimelineSlot], at: Date) -> TimelineSlot? {
    slots.last { $0.start <= at }
  }

  static func next(_ slots: [TimelineSlot], after slot: TimelineSlot) -> TimelineSlot? {
    slots.first { $0.index == slot.index + 1 }
  }

  static func coordinate(of stop: Loci_Trip_TripStop) -> CLLocationCoordinate2D? {
    guard stop.hasPoi, stop.poi.hasLatitude, stop.poi.hasLongitude, stop.poi.latitude != 0 || stop.poi.longitude != 0 else { return nil }
    return CLLocationCoordinate2D(latitude: stop.poi.latitude, longitude: stop.poi.longitude)
  }

  private static func distance(from a: Loci_Trip_TripStop, to b: Loci_Trip_TripStop, legs: [Loci_Trip_TripLeg]) -> Double? {
    if let leg = legs.first(where: { $0.fromName == a.name && $0.toName == b.name }), leg.distanceKm > 0 {
      return leg.distanceKm * 1000
    }
    guard let ca = coordinate(of: a), let cb = coordinate(of: b) else { return nil }
    return CLLocation(latitude: ca.latitude, longitude: ca.longitude).distance(from: CLLocation(latitude: cb.latitude, longitude: cb.longitude))
  }
}
```

Note: check the generated Swift names (`hasStartMinute`, `hasDurationMinutes`, `hasDayStartMinute`, `hasPoi`) with `grep -n "hasStartMinute\|hasDayStartMinute" ../loci-connect-proto/gen/swift/loci/trip/trip.pb.swift`; adjust if the generator named them differently.

- [ ] **Step 4: Run the tests, lint.** Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add loci/loci/Features/Trips/Model/DayTimeline.swift loci/lociTests/DayTimelineTests.swift
git commit -m "Add DayTimeline: a trip day as timed slots with distances"
```

---

### Task 7: TripPrefetch background task

**Files:**
- Create: `loci/loci/Core/Cache/TripPrefetch.swift`
- Modify: `loci/Info.plist` (`BGTaskSchedulerPermittedIdentifiers` ~5–8), `loci/loci/Core/AppDelegate.swift` (~9), `loci/loci/lociApp.swift` (`.onChange(of: scenePhase)` `.active` branch)
- Test: `loci/lociTests/TripPrefetchTests.swift`

**Interfaces:**
- Consumes: `LocalCache`, `DayTimeline.today`, `TripAPI.client.getTrip`, `ResultsAPI.localContext/fxRates`, `SavedAPI`.
- Produces: `@MainActor enum TripPrefetch { static let taskID = "com.fernandocorreia.loci.trip-prefetch"; static func register(); static func scheduleIfNeeded(); nonisolated static func nextBeginDate(trips: [Loci_Trip_TripDraft], now: Date, calendar: Calendar) -> Date?; static func run() async -> Bool; static func refreshTodayIfStale() async }`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

struct TripPrefetchTests {
  private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }
  private func trip(dayOn date: Date) -> Loci_Trip_TripDraft {
    var day = Loci_Trip_TripDay()
    day.date = Google_Protobuf_Timestamp(date: date)
    var t = Loci_Trip_TripDraft()
    t.days = [day]
    return t
  }

  @Test func schedulesTheEveningBeforeADayTomorrow() {
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))!
    let tomorrow = cal.date(from: DateComponents(year: 2026, month: 10, day: 8))!
    let begin = TripPrefetch.nextBeginDate(trips: [trip(dayOn: tomorrow)], now: now, calendar: cal)
    #expect(begin == cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 22)))
  }

  @Test func onTheDayItSchedulesSixHoursOut() {
    let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 8))!
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 10))!
    #expect(TripPrefetch.nextBeginDate(trips: [trip(dayOn: today)], now: now, calendar: cal) == now.addingTimeInterval(6 * 3600))
  }

  @Test func nothingWithinTwoDaysMeansNoSchedule() {
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!
    let later = cal.date(from: DateComponents(year: 2026, month: 10, day: 20))!
    #expect(TripPrefetch.nextBeginDate(trips: [trip(dayOn: later)], now: now, calendar: cal) == nil)
    #expect(TripPrefetch.nextBeginDate(trips: [], now: now, calendar: cal) == nil)
  }
}
```

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Write the implementation**

```swift
import BackgroundTasks
import Foundation
import LociConnectProto

/// Refreshes the next trip day's trip, forecast, money and saved places
/// before the day starts, so the phone has them with no signal. Best effort:
/// iOS decides when a BGAppRefreshTask runs; the foreground refresh on open
/// is the guarantee.
@MainActor enum TripPrefetch {
  static let taskID = "com.fernandocorreia.loci.trip-prefetch"
  static let staleAfter: TimeInterval = 3 * 3600

  static func register() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
      guard let task = task as? BGAppRefreshTask else { return }
      let work = Task { @MainActor in
        let done = await run()
        task.setTaskCompleted(success: done)
      }
      task.expirationHandler = { work.cancel() }
    }
  }

  /// Called after every trips load and every prefetch: one pending request at most.
  static func scheduleIfNeeded(trips: [Loci_Trip_TripDraft], now: Date = Date()) {
    guard let begin = nextBeginDate(trips: trips, now: now) else { return }
    let request = BGAppRefreshTaskRequest(identifier: taskID)
    request.earliestBeginDate = begin
    try? BGTaskScheduler.shared.submit(request)
  }

  /// 22:00 the evening before the next trip day within 48 h; on the day itself,
  /// six hours from now until the day ends.
  nonisolated static func nextBeginDate(trips: [Loci_Trip_TripDraft], now: Date, calendar: Calendar = .current) -> Date? {
    let horizon = now.addingTimeInterval(48 * 3600)
    let days = trips.flatMap(\.days).filter { $0.hasDate && !$0.travelDay }.map { calendar.startOfDay(for: $0.date.date) }
    guard let day = days.filter({ $0 <= horizon && calendar.date(byAdding: .day, value: 1, to: $0)! > now }).min() else { return nil }
    if calendar.isDate(day, inSameDayAs: now) {
      let candidate = now.addingTimeInterval(6 * 3600)
      return calendar.isDate(candidate, inSameDayAs: now) ? candidate : nil
    }
    let evening = calendar.date(byAdding: .hour, value: -2, to: day)!  // 22:00 the day before
    return max(evening, now)
  }

  /// The work itself, also used by the foreground refresh.
  static func run() async -> Bool {
    guard let trips = await LocalCache.shared.get(Loci_Trip_ListTripsResponse.self, kind: .trips, id: "all")?.value.trips else { return true }
    let now = Date()
    guard let trip = trips.first(where: { DayTimeline.today(in: $0, now: now.addingTimeInterval(24 * 3600)) != nil || DayTimeline.today(in: $0, now: now) != nil }) else { return true }
    var request = Loci_Trip_GetTripRequest()
    request.tripID = trip.id
    let sent = request
    let fresh = try? await rpc("", sent) { await TripAPI.client.getTrip(request: $0, headers: [:]) }
    if let fresh { try? await LocalCache.shared.put(fresh, kind: .trip, id: trip.id) }
    let day = DayTimeline.today(in: fresh ?? trip, now: now) ?? DayTimeline.today(in: fresh ?? trip, now: now.addingTimeInterval(24 * 3600))
    if let day, let (lat, lon) = coordinate(of: day) {
      let key = LocalCache.key(latitude: lat, longitude: lon)
      if let context = try? await ResultsAPI.localContext(latitude: lat, longitude: lon) { try? await LocalCache.shared.put(context, kind: .localContext, id: key) }
      if let fx = try? await ResultsAPI.fxRates(latitude: lat, longitude: lon) { try? await LocalCache.shared.put(fx, kind: .fx, id: key) }
    }
    scheduleIfNeeded(trips: trips, now: now)
    return fresh != nil
  }

  /// On open: refresh today's forecast when the copy is older than three hours.
  static func refreshTodayIfStale() async {
    guard let trips = await LocalCache.shared.get(Loci_Trip_ListTripsResponse.self, kind: .trips, id: "all")?.value.trips,
      let day = trips.lazy.compactMap({ DayTimeline.today(in: $0) }).first, let (lat, lon) = coordinate(of: day)
    else { return }
    let key = LocalCache.key(latitude: lat, longitude: lon)
    let copy = await LocalCache.shared.get(Loci_Localcontext_LocalContext.self, kind: .localContext, id: key)
    if let copy, Date().timeIntervalSince(copy.fetchedAt) < staleAfter { return }
    _ = await run()
  }

  nonisolated static func coordinate(of day: Loci_Trip_TripDay) -> (Double, Double)? {
    if day.hasCityLat, day.hasCityLon { return (day.cityLat, day.cityLon) }
    if let c = day.stops.lazy.compactMap(DayTimeline.coordinate(of:)).first { return (c.latitude, c.longitude) }
    return nil
  }
}
```

Saved lists are refreshed by the Saved hub's own cache-through on open; the task does not fetch them (spec B lists them, but the hub already writes them and the band never reads them: leave them out here to keep the 25 s budget for the trip and the forecast).

- [ ] **Step 4: Wire it**

- `loci/Info.plist`: add `<string>com.fernandocorreia.loci.trip-prefetch</string>` to the permitted identifiers array.
- `AppDelegate.didFinishLaunching`: `TripPrefetch.register()` after `SearchSessionController.registerBackgroundTask()`.
- `TripsView.load()`: after a `.fresh` result, `TripPrefetch.scheduleIfNeeded(trips: trips)`.
- `lociApp` `.onChange(of: scenePhase)` `.active`: add `Task { await TripPrefetch.refreshTodayIfStale() }`.

- [ ] **Step 5: Build, run tests, lint.** Expected: 3 new passed.

- [ ] **Step 6: Commit**

```bash
git add loci/loci/Core/Cache/TripPrefetch.swift loci/Info.plist loci/loci/Core/AppDelegate.swift loci/loci/lociApp.swift loci/loci/Features/Trips/UI/TripsView.swift loci/lociTests/TripPrefetchTests.swift
git commit -m "Prefetch the next trip day's trip and forecast in the background"
```

---

### Task 8: TripDayAttributes and the widget view

**Files:**
- Create: `loci/loci/Shared/TripDayAttributes.swift` (BOTH targets)
- Create: `loci/NearbyWalkWidget/TripDayLiveActivity.swift` (widget target; the folder is synchronized for that target)
- Modify: `loci/NearbyWalkWidget/NearbyWalkWidgetBundle.swift`, `loci/loci.xcodeproj/project.pbxproj` (via script)
- Test: `loci/lociTests/TripDayActivityTests.swift` (text helpers; controller tests come in Task 9)

**Interfaces:**
- Produces: `public nonisolated struct TripDayAttributes: ActivityAttributes { ContentState { phase: Phase, currentIndex: Int, currentName: String, slotEnd: Date, nextName: String?, nextDistanceMeters: Double?, stopsDone: Int }; tripId, dayId, cityName: String; stopCount: Int; startedAt: Date }`, `enum Phase: String, Codable, Sendable { case beforeFirst, atStop, between, done }`; `ContentState.nextText: String?` ("Next: Pantheon · 1.2 km"), `ContentState.progressText` ("2/5").

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing

@testable import loci

struct TripDayActivityTests {
  @Test func liveActivityTextIsSharedWithTheWidget() {
    var state = TripDayAttributes.ContentState(phase: .atStop, currentIndex: 1, currentName: "Pantheon", slotEnd: Date(), nextName: "Piazza Navona", nextDistanceMeters: 1234, stopsDone: 1)
    #expect(state.nextText == "Next: Piazza Navona · 1.2 km")
    #expect(state.progressText == "1/5".replacingOccurrences(of: "5", with: "5"))
    state.nextDistanceMeters = 40
    #expect(state.nextText == "Next: Piazza Navona · 40 m")
    state.nextName = nil
    #expect(state.nextText == nil)
  }
}
```

(Progress needs the count: make `progressText(of stopCount: Int) -> String` and assert `state.progressText(of: 5) == "1/5"`.)

- [ ] **Step 2: Add the shared file to both targets**

Create `loci/loci/Shared/TripDayAttributes.swift`:

```swift
import ActivityKit
import Foundation

/// The Live Activity for a trip day: the stop you are at, how long the plan
/// gives it, and what comes next. Compiled into the app (which starts and
/// updates it) and the widget extension (which draws it).
public nonisolated struct TripDayAttributes: ActivityAttributes {
  public nonisolated enum Phase: String, Codable, Hashable, Sendable { case beforeFirst, atStop, between, done }

  public nonisolated struct ContentState: Codable, Hashable, Sendable {
    public var phase: Phase
    public var currentIndex: Int
    public var currentName: String
    /// The end of the current slot; the widget counts down to it.
    public var slotEnd: Date
    public var nextName: String?
    public var nextDistanceMeters: Double?
    public var stopsDone: Int

    public init(phase: Phase, currentIndex: Int, currentName: String, slotEnd: Date, nextName: String? = nil, nextDistanceMeters: Double? = nil, stopsDone: Int) {
      self.phase = phase
      self.currentIndex = currentIndex
      self.currentName = currentName
      self.slotEnd = slotEnd
      self.nextName = nextName
      self.nextDistanceMeters = nextDistanceMeters
      self.stopsDone = stopsDone
    }
  }

  public var tripId: String
  public var dayId: String
  public var cityName: String
  public var stopCount: Int
  public var startedAt: Date

  public init(tripId: String, dayId: String, cityName: String, stopCount: Int, startedAt: Date) {
    self.tripId = tripId
    self.dayId = dayId
    self.cityName = cityName
    self.stopCount = stopCount
    self.startedAt = startedAt
  }
}

public nonisolated extension TripDayAttributes.ContentState {
  var nextText: String? {
    guard let nextName else { return nil }
    guard let meters = nextDistanceMeters else { return "Next: \(nextName)" }
    let distance = meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters.rounded())) m"
    return "Next: \(nextName) · \(distance)"
  }

  func progressText(of stopCount: Int) -> String { "\(stopsDone)/\(stopCount)" }
}
```

Then wire it into both targets with the `xcodeproj` gem (same gem `loci/scripts/add_widget_extension.rb` uses), from `loci/`:

```bash
bundle exec ruby -e '
require "xcodeproj"
project = Xcodeproj::Project.open("loci.xcodeproj")
ref = project.files.find { |f| f.path == "loci/Shared/NearbyWalkAttributes.swift" } or abort("shared ref not found")
group = ref.parent
new_ref = group.new_file("loci/Shared/TripDayAttributes.swift")
%w[loci NearbyWalkWidget].each do |name|
  t = project.targets.find { |t| t.name == name } or abort(name)
  t.add_file_references([new_ref])
end
project.save
puts "added to loci and NearbyWalkWidget"
'
```

Verify: `grep -c "TripDayAttributes.swift in Sources" loci/loci.xcodeproj/project.pbxproj` prints `2`.

- [ ] **Step 3: Write the widget view**

`loci/NearbyWalkWidget/TripDayLiveActivity.swift`:

```swift
import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island for a trip day: the stop you are at with
/// the time the plan gives it, and what comes next.
struct TripDayLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TripDayAttributes.self) { context in
      TripDayLockScreen(state: context.state, attributes: context.attributes)
        .activityBackgroundTint(Palette.paper)
        .activitySystemActionForegroundColor(Palette.forest)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.state.currentName).font(.headline).foregroundStyle(Palette.ink).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) { countdown(context.state).font(.headline).foregroundStyle(Palette.ink) }
        DynamicIslandExpandedRegion(.bottom) {
          if let next = context.state.nextText {
            Label(next, systemImage: "arrow.turn.down.right").font(.subheadline).foregroundStyle(Palette.terracotta).lineLimit(1)
          } else {
            Text(context.state.phase == .done ? "Day complete" : "Last stop of the day").font(.subheadline).foregroundStyle(.secondary)
          }
        }
      } compactLeading: {
        Image(systemName: "mappin.and.ellipse").foregroundStyle(Palette.terracotta)
      } compactTrailing: {
        countdown(context.state).font(.caption.monospacedDigit())
      } minimal: {
        Image(systemName: "mappin.and.ellipse").foregroundStyle(Palette.terracotta)
      }
    }
  }

  @ViewBuilder private func countdown(_ state: TripDayAttributes.ContentState) -> some View {
    if state.phase == .done {
      Text("Done")
    } else {
      Text(timerInterval: Date()...max(state.slotEnd, Date()), countsDown: true)
    }
  }
}

private struct TripDayLockScreen: View {
  let state: TripDayAttributes.ContentState
  let attributes: TripDayAttributes

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Day in \(attributes.cityName) · \(state.progressText(of: attributes.stopCount))", systemImage: "suitcase")
          .font(.caption.weight(.medium)).foregroundStyle(Palette.forest)
        Spacer()
        if state.phase != .done {
          Text(timerInterval: Date()...max(state.slotEnd, Date()), countsDown: true).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
      }
      Text(state.phase == .done ? "Day complete" : state.currentName).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
      if let next = state.nextText {
        Label(next, systemImage: "arrow.turn.down.right").font(.subheadline).foregroundStyle(Palette.terracotta).lineLimit(1)
      }
    }
    .padding(16)
  }
}
```

`Palette` is `private` in `NearbyWalkLiveActivity.swift`; change it to `enum Palette` (internal) so both widgets share it.

Add `TripDayLiveActivity()` to `NearbyWalkWidgetBundle.body`.

- [ ] **Step 4: Build both targets, run the test, lint.** `xcodebuild build -scheme "loci Beta"` builds the extension too. Expected green.

- [ ] **Step 5: Commit**

```bash
git add loci/loci/Shared/TripDayAttributes.swift loci/NearbyWalkWidget/TripDayLiveActivity.swift loci/NearbyWalkWidget/NearbyWalkWidgetBundle.swift loci/NearbyWalkWidget/NearbyWalkLiveActivity.swift loci/loci.xcodeproj/project.pbxproj loci/lociTests/TripDayActivityTests.swift
git commit -m "Trip-day Live Activity: shared attributes and the Lock Screen and Dynamic Island views"
```

---

### Task 9: TripDayActivityController

**Files:**
- Create: `loci/loci/Features/Trips/Services/TripDayActivityController.swift`
- Modify: `loci/lociTests/TripDayActivityTests.swift` (append)

**Interfaces:**
- Consumes: `DayTimeline`, `TimelineSlot`, `TripDayAttributes`, `POIProximityMonitor` (`arm(places:from:)`, `disarm()`; it takes `[Loci_Poi_POIDetailedInfo]`, so pass `slots.compactMap { $0.stop.hasPoi ? $0.stop.poi : nil }`), `UNUserNotificationCenter`.
- Produces: `@Observable @MainActor final class TripDayActivityController { static let shared; private(set) var running: Running?; struct Running { tripId, dayId: String; startedAt: Date; slots: [TimelineSlot] }; var isRunning: Bool; var liveActivitiesEnabled: Bool; func start(trip:day:now:) async; func advance(now:) async; func end() async; func refresh(now:) async; nonisolated static func state(slots:manualIndex:startedAt:now:) -> (TripDayAttributes.ContentState, shouldEnd: Bool) }`.

- [ ] **Step 1: Write the failing tests** (append; pure `state` function first)

```swift
  private func slot(_ i: Int, _ name: String, start: Date, minutes: Int, next: Double? = nil) -> TimelineSlot {
    var stop = Loci_Trip_TripStop()
    stop.id = name
    stop.name = name
    return TimelineSlot(stop: stop, index: i, start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)), coordinate: nil, distanceToNextMeters: next)
  }

  @Test func stateFollowsTheScheduleAndTheManualOverride() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let slots = [slot(0, "A", start: t0.addingTimeInterval(600), minutes: 60, next: 500), slot(1, "B", start: t0.addingTimeInterval(4500), minutes: 60)]
    let before = TripDayActivityController.state(slots: slots, manualIndex: nil, startedAt: t0, now: t0)
    #expect(before.0.phase == .beforeFirst && before.0.currentName == "A" && !before.shouldEnd)
    let during = TripDayActivityController.state(slots: slots, manualIndex: nil, startedAt: t0, now: t0.addingTimeInterval(1200))
    #expect(during.0.phase == .atStop && during.0.currentIndex == 0 && during.0.nextName == "B" && during.0.nextDistanceMeters == 500)
    let between = TripDayActivityController.state(slots: slots, manualIndex: nil, startedAt: t0, now: t0.addingTimeInterval(4300))
    #expect(between.0.phase == .between && between.0.stopsDone == 1)
    let manual = TripDayActivityController.state(slots: slots, manualIndex: 1, startedAt: t0, now: t0.addingTimeInterval(1200))
    #expect(manual.0.currentIndex == 1 && manual.0.phase == .atStop)
  }

  @Test func endsAfterTheLastSlotOrTwelveHours() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let slots = [slot(0, "A", start: t0, minutes: 60)]
    #expect(!TripDayActivityController.state(slots: slots, manualIndex: nil, startedAt: t0, now: t0.addingTimeInterval(80 * 60)).shouldEnd)
    let late = TripDayActivityController.state(slots: slots, manualIndex: nil, startedAt: t0, now: t0.addingTimeInterval(91 * 60))
    #expect(late.shouldEnd && late.0.phase == .done)
    let longDay = [slot(0, "A", start: t0, minutes: 240), slot(1, "B", start: t0.addingTimeInterval(13 * 3600), minutes: 60)]
    #expect(TripDayActivityController.state(slots: longDay, manualIndex: nil, startedAt: t0, now: t0.addingTimeInterval(12 * 3600 + 1)).shouldEnd)
  }

  @Test func stopsWithoutCoordinatesStillRunOnTheSchedule() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let slots = [slot(0, "A", start: t0, minutes: 60), slot(1, "B", start: t0.addingTimeInterval(4500), minutes: 60)]
    let state = TripDayActivityController.state(slots: slots, manualIndex: nil, startedAt: t0, now: t0.addingTimeInterval(60)).0
    #expect(state.phase == .atStop && state.nextName == "B" && state.nextDistanceMeters == nil)
    #expect(TripDayActivityController.fenceable(slots).isEmpty)
  }
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Write the controller**

```swift
@preconcurrency import ActivityKit
import CoreLocation
import Foundation
import LociConnectProto
import Observation
import UserNotifications

/// Runs one trip day as a Live Activity. The schedule (DayTimeline) decides
/// the current stop; a tap on Next or a geofence hit moves ahead of it until
/// the schedule catches up. Nothing here needs the server.
@Observable @MainActor final class TripDayActivityController {
  static let shared = TripDayActivityController()

  struct Running: Equatable {
    let tripId: String
    let dayId: String
    let cityName: String
    let startedAt: Date
    let slots: [TimelineSlot]
  }

  static let endAfterLast: TimeInterval = 30 * 60
  static let maxDuration: TimeInterval = 12 * 3600
  static let notificationCategory = "tripDay"
  private static let runningKey = "loci_trip_day_running"  // "tripId|dayId|startedAt"

  private(set) var running: Running?
  private(set) var manualIndex: Int?
  private var activity: Activity<TripDayAttributes>?
  private let fences = POIProximityMonitor()

  var isRunning: Bool { running != nil }
  var liveActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

  func start(trip: Loci_Trip_TripDraft, day: Loci_Trip_TripDay, now: Date = Date()) async {
    if running != nil { await end() }
    let slots = DayTimeline.slots(day: day, legs: trip.legs)
    guard !slots.isEmpty else { return }
    let run = Running(tripId: trip.id, dayId: day.id, cityName: day.cityName.isEmpty ? trip.cityName : day.cityName, startedAt: now, slots: slots)
    running = run
    manualIndex = nil
    let attributes = TripDayAttributes(tripId: trip.id, dayId: day.id, cityName: run.cityName, stopCount: slots.count, startedAt: now)
    let (state, _) = Self.state(slots: slots, manualIndex: nil, startedAt: now, now: now)
    activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
    UserDefaults.standard.set("\(trip.id)|\(day.id)|\(now.timeIntervalSince1970)", forKey: Self.runningKey)
    await fences.arm(places: Self.fenceable(slots), from: slots.first?.coordinate)
    await scheduleReminders(slots)
  }

  func advance(now: Date = Date()) async {
    guard let running else { return }
    let current = Self.effectiveIndex(slots: running.slots, manualIndex: manualIndex, now: now)
    manualIndex = min(current + 1, running.slots.count)
    await refresh(now: now)
  }

  func refresh(now: Date = Date()) async {
    guard let running else { return }
    let (state, shouldEnd) = Self.state(slots: running.slots, manualIndex: manualIndex, startedAt: running.startedAt, now: now)
    if shouldEnd {
      await end(final: state)
      return
    }
    if let activity {
      await activity.update(ActivityContent(state: state, staleDate: nil))
    }
  }

  func end(final: TripDayAttributes.ContentState? = nil) async {
    if let activity {
      let last = final ?? activity.content.state
      await activity.end(ActivityContent(state: last, staleDate: nil), dismissalPolicy: .default)
    }
    activity = nil
    running = nil
    manualIndex = nil
    UserDefaults.standard.removeObject(forKey: Self.runningKey)
    await fences.disarm()
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.reminderIDs)
  }

  /// Re-adopt an activity that survived a relaunch.
  func adoptIfRunning(trips: [Loci_Trip_TripDraft]) async {
    guard running == nil, let raw = UserDefaults.standard.string(forKey: Self.runningKey) else { return }
    let parts = raw.split(separator: "|").map(String.init)
    guard parts.count == 3, let seconds = TimeInterval(parts[2]),
      let live = Activity<TripDayAttributes>.activities.first(where: { $0.attributes.dayId == parts[1] }),
      let trip = trips.first(where: { $0.id == parts[0] }), let day = trip.days.first(where: { $0.id == parts[1] })
    else {
      UserDefaults.standard.removeObject(forKey: Self.runningKey)
      return
    }
    activity = live
    running = Running(tripId: trip.id, dayId: day.id, cityName: day.cityName.isEmpty ? trip.cityName : day.cityName, startedAt: Date(timeIntervalSince1970: seconds), slots: DayTimeline.slots(day: day, legs: trip.legs))
    await refresh()
  }

  // MARK: - Pure

  /// The slot index the activity shows: the manual override while it is ahead
  /// of the schedule, else the schedule.
  nonisolated static func effectiveIndex(slots: [TimelineSlot], manualIndex: Int?, now: Date) -> Int {
    let scheduled = DayTimeline.current(slots, at: now)?.index ?? -1
    return max(scheduled, manualIndex ?? -1)
  }

  nonisolated static func state(slots: [TimelineSlot], manualIndex: Int?, startedAt: Date, now: Date) -> (TripDayAttributes.ContentState, shouldEnd: Bool) {
    let count = slots.count
    let index = effectiveIndex(slots: slots, manualIndex: manualIndex, now: now)
    let lastEnd = slots.last?.end ?? startedAt
    let expired = now > lastEnd.addingTimeInterval(endAfterLast) || now > startedAt.addingTimeInterval(maxDuration)
    if index >= count || expired {
      let last = slots.last
      return (TripDayAttributes.ContentState(phase: .done, currentIndex: max(count - 1, 0), currentName: last?.stop.name ?? "", slotEnd: now, stopsDone: count), true)
    }
    if index < 0 {
      let first = slots[0]
      return (TripDayAttributes.ContentState(phase: .beforeFirst, currentIndex: 0, currentName: first.stop.name, slotEnd: first.start, nextName: first.stop.name, nextDistanceMeters: nil, stopsDone: 0), false)
    }
    let slot = slots[index]
    let next = DayTimeline.next(slots, after: slot)
    let phase: TripDayAttributes.Phase = now > slot.end && manualIndex == nil ? .between : .atStop
    return (TripDayAttributes.ContentState(
      phase: phase, currentIndex: index, currentName: slot.stop.name,
      slotEnd: phase == .between ? (next?.start ?? slot.end) : slot.end,
      nextName: next?.stop.name, nextDistanceMeters: slot.distanceToNextMeters,
      stopsDone: phase == .between ? index + 1 : index
    ), false)
  }

  nonisolated static func fenceable(_ slots: [TimelineSlot]) -> [Loci_Poi_POIDetailedInfo] {
    slots.compactMap { $0.coordinate != nil && $0.stop.hasPoi ? $0.stop.poi : nil }
  }

  // MARK: - Reminders

  private static var reminderIDs: [String] { (0..<40).map { "trip-day-\($0)" } }

  private func scheduleReminders(_ slots: [TimelineSlot]) async {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: Self.reminderIDs)
    guard let running else { return }
    for slot in slots.dropLast() {
      guard let next = DayTimeline.next(slots, after: slot), slot.end > Date() else { continue }
      let content = UNMutableNotificationContent()
      content.title = "Time for \(next.stop.name)?"
      content.body = "The plan moves on from \(slot.stop.name). Tap to advance."
      content.categoryIdentifier = Self.notificationCategory
      content.threadIdentifier = "trip-day"
      content.userInfo = ["tripId": running.tripId, "dayId": running.dayId, "index": next.index]
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(slot.end.timeIntervalSinceNow, 1), repeats: false)
      try? await center.add(UNNotificationRequest(identifier: "trip-day-\(slot.index)", content: content, trigger: trigger))
    }
  }
}
```

`POIProximityMonitor.arrived(at:)` posts to a closure or notification: read its implementation (`Features/Nearby/Services/POIProximityMonitor.swift:73`) and hook the controller the same way the walk does (if it takes an `onArrive` closure, pass `{ [weak self] _ in Task { await self?.advance() } }` in `start`; if it posts a local notification only, leave the fence as the walk's "nudge" and rely on Next).

- [ ] **Step 4: Run the tests, lint.** Expected: the three new tests pass.

- [ ] **Step 5: Commit**

```bash
git add loci/loci/Features/Trips/Services/TripDayActivityController.swift loci/lociTests/TripDayActivityTests.swift
git commit -m "TripDayActivityController: the schedule drives the Live Activity, Next and fences move ahead of it"
```

---

### Task 10: Today band, editor controls, notification tap

**Files:**
- Create: `loci/loci/Features/Trips/UI/TodayBand.swift`
- Modify: `loci/loci/Features/Trips/UI/TripsView.swift`, `loci/loci/Features/Trips/UI/TripEditorView.swift` (day header), `loci/loci/Core/Routing/AppRouter.swift` (`pendingTrip`), `loci/loci/Core/Notifications/PushNotificationManager.swift` (`didReceive`), `loci/loci/Features/Auth/Services/AuthService.swift` (`logout`)

- [ ] **Step 1: TodayBand**

```swift
import LociConnectProto
import SwiftUI

/// "Today" above the trips list when a cached trip has a day dated today:
/// the city, the first stops, and the way into the Live Activity.
struct TodayBand: View {
  let trip: Loci_Trip_TripDraft
  let day: Loci_Trip_TripDay
  private let controller = TripDayActivityController.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Today · \(day.cityName.isEmpty ? trip.cityName : day.cityName)").lociCoordStyle(10)
      Text(trip.title.isEmpty ? "Day \(day.dayNumber)" : trip.title).font(.lociHeadline(17)).foregroundStyle(Color.lociInk)
      ForEach(day.stops.prefix(3), id: \.id) { stop in
        Label(stop.name, systemImage: "mappin").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk).lineLimit(1)
      }
      HStack(spacing: 8) {
        if controller.isRunning, controller.running?.dayId == day.id {
          NavigationLink(value: trip.id) { Label("Open today", systemImage: "arrow.right.circle") }
          Button("Next", systemImage: "forward.end") { Task { await controller.advance() } }
          Button("Done", systemImage: "checkmark") { Task { await controller.end() } }
        } else {
          Button("Start today", systemImage: "play.fill") { Task { await controller.start(trip: trip, day: day) } }
            .disabled(!controller.liveActivitiesEnabled)
        }
      }
      .buttonStyle(MusePillButtonStyle())
      if !controller.liveActivitiesEnabled {
        Text("Turn on Live Activities for Loci in Settings to follow the day from the Lock Screen.").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .lociCard()
  }
}
```

In `TripsView`, above the list (as the first `Section` row, clear background): `if let (trip, day) = todayTrip { TodayBand(trip: trip, day: day) }` where `private var todayTrip: (Loci_Trip_TripDraft, Loci_Trip_TripDay)? { trips.lazy.compactMap { t in DayTimeline.today(in: t).map { (t, $0) } }.first }`. After `load()` call `await TripDayActivityController.shared.adoptIfRunning(trips: trips)`.

- [ ] **Step 2: Editor day header controls**

In `daySection`'s header `HStack`, after the day label: `if let trip, DayTimeline.today(in: trip)?.id == day.id { Spacer(); TodayControls(trip: trip, day: day) }` where `TodayControls` is the same three-button group as the band (extract it from `TodayBand` into `struct TodayControls: View` in `TodayBand.swift` and reuse it).

- [ ] **Step 3: Notification tap and router**

- `AppRouter`: `public var pendingTrip: (tripId: String, dayId: String)?` is not `Equatable` for `onChange`; use `public struct TripLink: Hashable, Sendable { public let tripId: String; public let dayId: String }` and `public var pendingTrip: TripLink?`, plus `public func open(trip: TripLink) { selectedTab = .calendar; pendingTrip = trip }`.
- `PushNotificationManager.didReceive`: before the `SessionLink` branch, `if response.notification.request.content.categoryIdentifier == TripDayActivityController.notificationCategory, let tripId = userInfo["tripId"] as? String, let dayId = userInfo["dayId"] as? String { Task { await TripDayActivityController.shared.advance() }; AppRouter.shared.open(trip: .init(tripId: tripId, dayId: dayId)) }`.
- `TripsView`: `.onChange(of: router.pendingTrip) { _, link in if let link { path.append(link.tripId); router.pendingTrip = nil } }` (the view already navigates by trip id string via `navigationDestination(for: String.self)`; add a `@State private var path = NavigationPath()` if it does not have one and bind the stack to it).
- `AuthService.logout()`: after `PushRegistration.shared.unregister()`, add `await TripDayActivityController.shared.end()` and `await LocalCache.shared.clear()`.

- [ ] **Step 4: Build, run the full test suite, lint.** Expected green.

- [ ] **Step 5: Commit**

```bash
git add loci/loci/Features/Trips/UI/TodayBand.swift loci/loci/Features/Trips/UI/TripsView.swift loci/loci/Features/Trips/UI/TripEditorView.swift loci/loci/Core/Routing/AppRouter.swift loci/loci/Core/Notifications/PushNotificationManager.swift loci/loci/Features/Auth/Services/AuthService.swift
git commit -m "Today band and day controls start, advance and end the trip-day activity; sign-out clears the cache"
```

---

### Task 11: Design preview, docs, PR

**Files:**
- Modify: `loci/loci/Core/DesignPreview.swift` (new case `tripDay`, fixture `Loci_Trip_TripDraft.previewRome`)
- Create: `docs/ios/14-offline-trip-day.md`
- Modify: `docs/ios/ROADMAP.md` (Phase 2 items 2 and 3), `docs/ios/ARCHITECTURE.md` (§13 gaps, §14 study path)

- [ ] **Step 1: Preview**

Add `case tripDay` rendering `ScrollView { VStack { TodayBand(trip: .previewRome, day: Loci_Trip_TripDraft.previewRome.days[0]) ; TripDayLockScreenPreviewCard } }` on `Color.lociPaper`; the fixture has three stops (Colosseum, Roman Forum, Pantheon) with coordinates and `date` = today at midnight in the current calendar. Screenshot with `xcrun simctl launch … -designPreview tripDay` and check the band renders.

- [ ] **Step 2: Docs**

`docs/ios/14-offline-trip-day.md` with the table of pieces (LocalCache, cacheThrough, CacheChip, TripPrefetch, DayTimeline, TripDayActivityController, TripDayAttributes, TripDayLiveActivity, TodayBand), the timing rules, the activity phases, the "Connect to edit" rule, and how to test on a device (airplane mode after one open; Start today; Next; lock the phone). ROADMAP: strike items 2 and 3 with a pointer. ARCHITECTURE §13: remove the offline gap, add the trip-day activity; §14: add `Core/Cache/LocalCache.swift` and `Features/Trips/Model/DayTimeline.swift` to the study path.

- [ ] **Step 3: Full verification**

Run: full `xcodebuild test` on the simulator, `scripts/format.sh --skip-install --lint-only`, and a `xcodebuild build` of the `loci Beta` scheme (extension included). Expected: all tests pass, 0 lint violations.

- [ ] **Step 4: Commit and open the PR**

```bash
git add loci/loci/Core/DesignPreview.swift docs/ios/14-offline-trip-day.md docs/ios/ROADMAP.md docs/ios/ARCHITECTURE.md
git commit -m "Offline trip day: preview, docs, roadmap"
git push -u origin feat/ios-offline-trip-day
gh pr create --title "Offline trip day: cached trips and saved places, trip prefetch, trip-day Live Activity" --body "Phase 2B (spec docs/superpowers/specs/2026-09-24-offline-trip-day-design.md, plan docs/superpowers/plans/2026-09-24-offline-trip-day.md). Read-only proto cache with cache-through loading and the offline chip; BGAppRefresh prefetch of the next trip day; DayTimeline; trip-day Live Activity in the existing widget target; Today band and editor controls. Tests: LocalCache, cacheThrough, DayTimeline, TripPrefetch, TripDayActivity."
```

Device check after TestFlight: open Trips online, enable airplane mode, reopen: the list and a trip render with "Offline · last updated …"; edits disabled; on a trip day, Start today puts the activity on the Lock Screen and Next moves it.
