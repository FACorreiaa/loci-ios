# iOS trip plan (Plan section + planner proposals) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On iOS a traveller can plan a trip two ways.
- **By hand:** a Plan section on the trip page sets dates, a hotel per city by stars, and flight searches.
- **With the planner:** "Ask the planner" opens a sheet where the chat agent's proposals appear as cards to confirm or dismiss.

**Architecture:**
- **Pure rules** in `TripPlan` (cities, coordinates, stars, hotel filter) are unit-tested.
- **Plan section.** `TripPlanSection` is a `List` section, like `TripPreferencesSection`. It hands edits back to `TripEditorView`, which runs them through its existing `apply(_:_:_:)` helper. That helper already passes `baseVersion`, adopts the returned trip and raises the conflict alert.
- **Reads** (hotels near a city, flight links) go through `TripPlanAPI`.
- **Trip id on the stream:** `SearchEnvelope`/`start(...)` carry `tripId` into `ChatRequest.trip_id`.
- **Proposals in `SearchState`:** it collects `action_proposal` payloads into `proposals`.
- **`TripPlannerSheet`:** it starts a trip-bound search through `SearchSessionController.shared` and renders `controller.state.proposals` as `TripActionCardView`s. Apply and Dismiss go through `TripActionsModel`, behind the `TripActionService` protocol, so they can be tested.
- **Why a sheet:** a proposal-only turn sends no `start` event, so the results screen, which opens on `startedLink`, would never show.

**Tech Stack:** SwiftUI (iOS 17+, `@Observable`), Connect-Swift, SwiftProtobuf, Swift Testing.

**Spec:** loci-connect-server `docs/superpowers/specs/2026-09-30-trip-workflow-agent-actions-design.md` (Surfaces, iOS). This is plan 4 of 5. The server and web parts are live.

## Global Constraints

- **Proto:** iOS builds against the local `../../loci-connect-proto` (main already has every type). CI checks out the proto default branch, so there is nothing to bump.
- **Writes:** every trip write goes through `TripEditorView.apply`, so `baseVersion` and the conflict alert ("This trip changed on another device") are reused, not duplicated.
- **Prices:** Loci never shows a price; flight cards show links.
- **SwiftLint:** `cyclomatic_complexity` errors at 30 and warns at 20. Keep `SearchState.apply` flat by putting proposal handling in a helper, as `applyGastronomy` does.
- **Worktree:** `/private/tmp/ios-trip-plan`, branch `feat/ios-trip-plan`. Run `ln -sfn <proto checkout> /private/tmp/loci-connect-proto` before building, because the project resolves `../../loci-connect-proto` relative to `loci/`. Remove the link afterwards.
- **Build:** `xcodebuild -project loci/loci.xcodeproj -scheme "loci Beta" -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/ios-trip-dd build`.
- **Test:** `xcodebuild test -project loci/loci.xcodeproj -scheme "loci Beta" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:lociTests -derivedDataPath /private/tmp/ios-trip-dd`. Use whichever simulator `xcrun simctl list devices available` shows.
- **Disk space** is tight: delete `/private/tmp/ios-trip-dd` when done.

## Review Focus

1. **A trip edited on another device while the Plan section is open:** saving raises the existing conflict alert and never overwrites. Pinned in Task 5, by reusing `apply`.
2. **A city with no position:** the section says hotels can't be searched instead of searching at 0,0. Pinned in Task 1.
3. **A proposal card confirmed after the trip changed:** the card says so and stays, and the sheet reloads the trip's version. Pinned in Task 3.
4. **Normal searches** (Discover, Assistant) send no `trip_id` and show no cards. Pinned in Task 2.
5. **The same proposal event replayed on resume** shows one card. Pinned in Task 2.

---

### Task 1: TripPlan rules

**Files:**
- Create `loci/loci/Features/Trips/Model/TripPlan.swift`.
- Test in `loci/lociTests/TripPlanTests.swift`.

- [ ] **Step 1: Failing tests**

```swift
import LociConnectProto
import Testing

@testable import loci

struct TripPlanTests {
  private func trip(city: String = "Lisbon", days: [Loci_Trip_TripDay], cities: [String] = []) -> Loci_Trip_TripDraft {
    var t = Loci_Trip_TripDraft()
    t.cityName = city
    t.days = days
    t.cities = cities.map { name in var c = Loci_Trip_TripCity(); c.cityName = name; return c }
    return t
  }

  private func day(_ city: String, lat: Double? = nil, lon: Double? = nil) -> Loci_Trip_TripDay {
    var d = Loci_Trip_TripDay()
    d.cityName = city
    if let lat { d.cityLat = lat }
    if let lon { d.cityLon = lon }
    return d
  }

  @Test func citiesAreTheMultiCityListElseTheTripsCity() {
    #expect(TripPlan.cities(of: trip(days: [])) == ["Lisbon"])
    #expect(TripPlan.cities(of: trip(days: [], cities: ["Lisbon", "Porto"])) == ["Lisbon", "Porto"])
  }

  @Test func coordinateIsTheFirstDaySpentThere() {
    let t = trip(days: [day("Lisbon"), day("Porto", lat: 41.1, lon: -8.6), day("", lat: 38.7, lon: -9.1)])
    #expect(TripPlan.coordinate(of: "Porto", in: t)?.latitude == 41.1)
    #expect(TripPlan.coordinate(of: "lisbon", in: t)?.latitude == 38.7, "an unnamed day is the trip's own city")
    #expect(TripPlan.coordinate(of: "Faro", in: t) == nil)
    #expect(TripPlan.coordinate(of: "Lisbon", in: trip(days: [day("Lisbon")])) == nil, "no position, no search")
  }

  @Test func starsReadNumbersBeforeGlyphs() {
    #expect(TripPlan.stars("4") == 4)
    #expect(TripPlan.stars("4.5") == 4.5)
    #expect(TripPlan.stars("4★") == 4)
    #expect(TripPlan.stars("★★★") == 3)
    #expect(TripPlan.stars("") == nil)
    #expect(TripPlan.stars("luxury") == nil)
  }

  @Test func hotelsFilterToTheWholeStarBestRatedFirst() {
    func hotel(_ name: String, _ stars: String, _ rating: Double) -> Loci_Favorites_V1_HotelDetails {
      var h = Loci_Favorites_V1_HotelDetails()
      h.name = name
      h.starRating = stars
      h.rating = rating
      return h
    }
    let all = [hotel("A", "5", 4.8), hotel("B", "4.5", 4.2), hotel("C", "", 4.9), hotel("D", "4", 4.6)]
    #expect(TripPlan.hotels(all, stars: 4).map(\.name) == ["D", "B"])
    #expect(TripPlan.hotels(all, stars: 0).map(\.name) == ["C", "A", "D", "B"], "any keeps unrated")
  }
}
```

Check the Swift type of `Loci_Favorites_V1_HotelDetails.rating` in `loci-connect-proto/gen/swift/loci/favorites/v1/favorites.pb.swift`. If it is optional or Float, adapt the test and the code.

- [ ] **Step 2:** Run the test command with `-only-testing:lociTests/TripPlanTests`.
Expected: FAIL to compile (no `TripPlan`).

- [ ] **Step 3: Implement**

```swift
import Foundation
import LociConnectProto

/// The rules behind the trip page's Plan section (web: lib/api/trip-plan.ts):
/// which cities a stay is for, where a city is, and hotels by stars.
nonisolated enum TripPlan {
  /// The cities a stay can be set for: a multi-city trip's, else the trip's own.
  static func cities(of trip: Loci_Trip_TripDraft) -> [String] {
    if !trip.cities.isEmpty { return trip.cities.map(\.cityName) }
    return trip.cityName.isEmpty ? [] : [trip.cityName]
  }

  /// Where a city of the trip is: the first day spent there that has a position.
  /// A day with no city name is the trip's own city.
  static func coordinate(of city: String, in trip: Loci_Trip_TripDraft) -> (latitude: Double, longitude: Double)? {
    let want = city.trimmingCharacters(in: .whitespaces).lowercased()
    let isPrimary = trip.cityName.trimmingCharacters(in: .whitespaces).lowercased() == want
    for day in trip.days {
      let name = day.cityName.trimmingCharacters(in: .whitespaces).lowercased()
      guard name == want || (name.isEmpty && isPrimary) else { continue }
      guard day.hasCityLat, day.hasCityLon else { continue }
      return (day.cityLat, day.cityLon)
    }
    return nil
  }

  /// A hotel's stars as a number: "4", "4.5", "4★", "★★★★". A number wins.
  static func stars(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    let digits = trimmed.prefix { $0.isNumber || $0 == "." }
    if !digits.isEmpty, let value = Double(digits) { return (value > 0 && value <= 5) ? value : nil }
    let glyphs = trimmed.filter { $0 == "★" }.count
    return (1...5).contains(glyphs) ? Double(glyphs) : nil
  }

  /// Hotels whose whole stars equal `stars`, best rated first. 0 is any rating
  /// and keeps unrated hotels; a chosen rating drops them.
  static func hotels(_ hotels: [Loci_Favorites_V1_HotelDetails], stars want: Int) -> [Loci_Favorites_V1_HotelDetails] {
    hotels
      .filter { hotel in
        guard want > 0 else { return true }
        guard let value = stars(hotel.starRating) else { return false }
        return Int(value.rounded(.down)) == want
      }
      .sorted { $0.rating > $1.rating }
  }

  /// The stay set for a city, matched loosely.
  static func stay(for city: String, in trip: Loci_Trip_TripDraft) -> Loci_Trip_TripStay? {
    trip.stays.first { $0.cityName.caseInsensitiveCompare(city) == .orderedSame }
  }
}
```

The day's own coordinates are used, not `TripPrefetch.coordinate`'s stop fallback. A stop's pin is not the city.

- [ ] **Step 4:** Run the tests.
Expected: PASS.

- [ ] **Step 5:** Commit: `feat(ios): rules for the trip's Plan section`.

---

### Task 2: The stream carries the trip and its proposals

**Files:**
- Modify `Features/Search/Model/SearchEnvelope.swift`, `Features/Search/SearchSessionController.swift` and `Features/Search/Model/SearchState.swift`.
- Test in `loci/lociTests/TripProposalStreamTests.swift`.

- [ ] **Step 1: Failing tests**

```swift
import LociConnectProto
import Testing

@testable import loci

struct TripProposalStreamTests {
  private func proposal(_ id: String, event: String) -> Loci_Chat_StreamEvent {
    var e = Loci_Chat_StreamEvent()
    e.eventID = event
    e.actionProposal.proposal.id = id
    e.actionProposal.proposal.summary = "Set dates"
    return e
  }

  @Test func proposalsCollectOncePerProposal() {
    var state = SearchState()
    _ = state.apply(proposal("p1", event: "e1"))
    _ = state.apply(proposal("p2", event: "e2"))
    _ = state.apply(proposal("p1", event: "e3"))  // replayed under a new event id
    #expect(state.proposals.map(\.id) == ["p1", "p2"])
  }

  @Test func tripIdGoesOnTheRequestOnlyWhenSet() {
    var envelope = SearchEnvelope(
      sessionId: nil, requestId: "r", profileId: nil, lastEventId: nil, query: "x", cityName: nil, domain: nil,
      latitude: nil, longitude: nil, startedAt: .now, finished: false, notified: false)
    #expect(!SearchSessionController.request(from: envelope, resuming: false).hasTripID)
    envelope.tripId = "t1"
    #expect(SearchSessionController.request(from: envelope, resuming: false).tripID == "t1")
  }
}
```

Match `SearchEnvelope`'s memberwise initialiser to its real stored properties; read the struct first.

- [ ] **Step 2:** Run with `-only-testing:lociTests/TripProposalStreamTests`.
Expected: FAIL to compile.

- [ ] **Step 3: Implement**
  - **`SearchEnvelope`:** add `/// The trip this search is about: its turns propose changes to it (ChatRequest.trip_id). var tripId: String?` after `routeData`. Old saved envelopes decode it as nil.
  - **`SearchSessionController.start(...)`:** add the parameter `tripId: String? = nil` after `suggestOrder`, and pass `tripId: tripId` into the `SearchEnvelope(...)` it builds.
  - **`request(from:resuming:)`:** before `return`, add `if let tripId = envelope.tripId, !tripId.isEmpty { request.tripID = tripId }`.
  - **`SearchState`:** add `/// Changes the planner proposes to the search's trip (ChatRequest.trip_id), in arrival order. var proposals: [Loci_Chat_ActionProposal] = []`, then the helper:

    ```swift
    /// A trip-action proposal: kept once, however many times a resumed stream replays it.
    private mutating func applyTripAction(_ payload: Loci_Chat_StreamEvent.OneOf_Payload) -> Bool {
      guard case .actionProposal(let wrapper) = payload else { return false }
      if wrapper.hasProposal, !proposals.contains(where: { $0.id == wrapper.proposal.id }) {
        proposals.append(wrapper.proposal)
      }
      return true
    }
    ```

    Wire it in with `if applyMultiCity(event, payload) || applyGastronomy(payload) || applyTripAction(payload) { return nil }`. Leave `.actionProposal` in the switch's no-op case, which keeps the switch exhaustive. Update that case's comment to "handled above".

- [ ] **Step 4:** Run all of `lociTests`.
Expected: PASS, including the existing SearchState and resume tests.

- [ ] **Step 5:** Commit: `feat(ios): searches can be about a trip and carry its proposals`.

---

### Task 3: Apply and dismiss

**Files:**
- Create `Features/Trips/Services/TripActionService.swift` and `Features/Trips/Model/TripActionsModel.swift`.
- Test in `loci/lociTests/TripActionsModelTests.swift`.

- [ ] **Step 1: Failing tests**

```swift
import LociConnectProto
import Testing

@testable import loci

actor StubTripActions: TripActionService {
  var applyResult: Result<Loci_Chat_ApplyTripActionResponse, TripActionError> = .success(.init())
  private(set) var applied: [(String, Int?, Int64)] = []
  private(set) var dismissed: [String] = []

  func setApply(_ result: Result<Loci_Chat_ApplyTripActionResponse, TripActionError>) { applyResult = result }

  func apply(proposalID: String, option: Int?, baseVersion: Int64) async throws(TripActionError) -> Loci_Chat_ApplyTripActionResponse {
    applied.append((proposalID, option, baseVersion))
    return try applyResult.get()
  }

  func dismiss(proposalID: String) async throws(TripActionError) {
    dismissed.append(proposalID)
  }
}

@MainActor
struct TripActionsModelTests {
  private func proposal(_ id: String) -> Loci_Chat_ActionProposal {
    var p = Loci_Chat_ActionProposal()
    p.id = id
    p.tripID = "t1"
    return p
  }

  @Test func applySendsTheVersionAndReturnsTheTrip() async {
    let stub = StubTripActions()
    var response = Loci_Chat_ApplyTripActionResponse()
    response.trip.version = 4
    await stub.setApply(.success(response))
    let model = TripActionsModel(service: stub)
    let trip = await model.apply(proposal("p1"), option: 1, baseVersion: 3)
    #expect(trip?.version == 4)
    #expect(model.state("p1") == .applied)
    let calls = await stub.applied
    #expect(calls.first?.0 == "p1" && calls.first?.1 == 1 && calls.first?.2 == 3)
  }

  @Test func aStaleTripKeepsTheCardAndSaysSo() async {
    let stub = StubTripActions()
    await stub.setApply(.failure(TripActionError(kind: .stale, message: "x")))
    let model = TripActionsModel(service: stub)
    let trip = await model.apply(proposal("p1"), option: nil, baseVersion: 3)
    #expect(trip == nil)
    if case .failed(let text) = model.state("p1") { #expect(text.contains("changed")) } else { Issue.record("expected failed") }
    #expect(model.needsReload)
  }

  @Test func noVersionYetAppliesNothing() async {
    let stub = StubTripActions()
    let model = TripActionsModel(service: stub)
    #expect(await model.apply(proposal("p1"), option: nil, baseVersion: nil) == nil)
    #expect(await stub.applied.isEmpty)
  }

  @Test func dismissTellsTheServerAndHidesTheCard() async {
    let stub = StubTripActions()
    let model = TripActionsModel(service: stub)
    await model.dismiss(proposal("p2"))
    #expect(await stub.dismissed == ["p2"])
    #expect(model.state("p2") == .dismissed)
  }
}
```

- [ ] **Step 2:** Run with `-only-testing:lociTests/TripActionsModelTests`.
Expected: FAIL to compile.

- [ ] **Step 3: Implement** `TripActionService.swift`:

```swift
import Connect
import Foundation
import LociConnectProto

/// Why a proposed trip change could not be applied, in the card's words.
nonisolated struct TripActionError: Error, Equatable, Sendable {
  enum Kind: Equatable, Sendable { case stale, gone, invalid, other }
  let kind: Kind
  let message: String

  init(kind: Kind, message: String) {
    self.kind = kind
    self.message = message
  }

  /// FailedPrecondition is a stale trip ("trip version conflict") or a
  /// proposal already used, dismissed or expired; the text tells them apart.
  init(_ error: ConnectError?, fallback: String) {
    let text = error?.message ?? ""
    switch error?.code {
    case .failedPrecondition: kind = text.contains("version") ? .stale : .gone
    case .notFound: kind = .gone
    case .invalidArgument: kind = .invalid
    default: kind = .other
    }
    message = text.isEmpty ? fallback : text
  }

  var userMessage: String {
    switch kind {
    case .stale: "This trip changed since the suggestion. Ask again for a fresh one."
    case .gone: "This suggestion was already used or has expired."
    case .invalid: "That change can't be made to this trip."
    case .other: "Couldn't make that change. Try again."
    }
  }
}

/// ApplyTripAction / DismissTripAction. A protocol so the model can be tested.
nonisolated protocol TripActionService: Sendable {
  func apply(proposalID: String, option: Int?, baseVersion: Int64) async throws(TripActionError) -> Loci_Chat_ApplyTripActionResponse
  func dismiss(proposalID: String) async throws(TripActionError)
}

nonisolated struct ConnectTripActionService: TripActionService {
  private let client = Loci_Chat_ChatServiceClient(client: ConnectTransport.shared.protocolClient)

  func apply(proposalID: String, option: Int?, baseVersion: Int64) async throws(TripActionError) -> Loci_Chat_ApplyTripActionResponse {
    var request = Loci_Chat_ApplyTripActionRequest()
    request.proposalID = proposalID
    if let option { request.optionIndex = Int32(option) }
    request.baseVersion = baseVersion
    let sent = request
    let response = await withAuthRetry { await client.applyTripAction(request: sent, headers: [:]) }
    if let message = response.message { return message }
    throw TripActionError(response.error, fallback: "Couldn't make that change.")
  }

  func dismiss(proposalID: String) async throws(TripActionError) {
    var request = Loci_Chat_DismissTripActionRequest()
    request.proposalID = proposalID
    let sent = request
    let response = await withAuthRetry { await client.dismissTripAction(request: sent, headers: [:]) }
    if response.message == nil { throw TripActionError(response.error, fallback: "Couldn't dismiss that.") }
  }
}
```

`TripActionsModel.swift`:

```swift
import Foundation
import LociConnectProto
import Observation

/// The state of the planner's proposal cards (web: TripActionCard). Nothing
/// changes until the traveller taps; the server applies a proposal once,
/// against the trip version the card was shown with.
@MainActor @Observable final class TripActionsModel {
  enum CardState: Equatable { case ready, applying, failed(String), applied, dismissed }

  private(set) var states: [String: CardState] = [:]
  /// Set when a card met a stale trip: the sheet reloads the trip's version.
  private(set) var needsReload = false
  private let service: TripActionService

  init(service: TripActionService = ConnectTripActionService()) {
    self.service = service
  }

  func state(_ id: String) -> CardState { states[id] ?? .ready }

  /// The trip as it now is, or nil when nothing changed. `baseVersion` is nil
  /// until the trip has loaded; a card cannot be applied before that.
  func apply(_ proposal: Loci_Chat_ActionProposal, option: Int?, baseVersion: Int64?) async -> Loci_Trip_TripDraft? {
    guard let baseVersion, state(proposal.id) != .applying else { return nil }
    states[proposal.id] = .applying
    do {
      let response = try await service.apply(proposalID: proposal.id, option: option, baseVersion: baseVersion)
      states[proposal.id] = .applied
      return response.hasTrip ? response.trip : nil
    } catch {
      states[proposal.id] = .failed(error.userMessage)
      if error.kind == .stale { needsReload = true }
      return nil
    }
  }

  func dismiss(_ proposal: Loci_Chat_ActionProposal) async {
    states[proposal.id] = .dismissed
    try? await service.dismiss(proposalID: proposal.id)  // a courtesy to the server; the card goes either way
  }

  func reloaded() { needsReload = false }
}
```

Check two things against the real code:
- **`withAuthRetry`'s signature** in `Core/Network/APIError+Connect.swift`, and match it.
- **`ApplyTripActionResponse.hasTrip`**. If the generated message lacks `hasTrip`, use `response.trip`.

- [ ] **Step 4:** Run the tests.
Expected: PASS.

- [ ] **Step 5:** Commit: `feat(ios): apply and dismiss the planner's proposals`.

---

### Task 4: Plan reads (`TripPlanAPI`)

**Files:**
- Create `Features/Trips/Services/TripPlanAPI.swift`. These are thin RPC wrappers with no unit tests, like `TripAPI`.

- [ ] **Step 1: Implement**

```swift
import Foundation
import LociConnectProto

/// The Plan section's reads: hotels near a city, and the flight search links
/// the server builds. Writes go through TripEditorView.apply.
nonisolated enum TripPlanAPI {
  static func hotelsNear(latitude: Double, longitude: Double) async throws -> [Loci_Favorites_V1_HotelDetails] {
    var request = Loci_Favorites_V1_GetNearbyHotelsRequest()
    request.latitude = latitude
    request.longitude = longitude
    request.radiusKm = 5
    request.limit = 40
    return try await rpc("Could not look up hotels.", request) { await ResultsAPI.favorites.getNearbyHotels(request: $0, headers: [:]) }.hotels
  }

  static func flightLinks(_ search: FlightSearch) async throws(TripRPCError) -> [Loci_Trip_FlightLink] {
    var request = Loci_Trip_BuildFlightLinksRequest()
    request.origin = search.originPlace
    request.destination = search.destinationPlace
    request.departDate = search.departDate
    if let ret = search.returnDate { request.returnDate = ret }
    request.passengers = Int32(search.passengers)
    request.cabin = search.cabin
    return try await TripAPI.call("Could not build the flight search.", request) {
      await TripAPI.client.buildFlightLinks(request: $0, headers: [:])
    }.links
  }
}

/// One flight search from the Plan section's form.
nonisolated struct FlightSearch: Equatable, Sendable {
  var origin = ""
  var destination = ""
  var departDate = ""      // YYYY-MM-DD
  var returnDate: String?  // YYYY-MM-DD
  var passengers = 1
  var cabin: Loci_Trip_FlightCabin = .unspecified

  var originPlace: Loci_Trip_FlightPlace { var p = Loci_Trip_FlightPlace(); p.name = origin.trimmingCharacters(in: .whitespaces); return p }
  var destinationPlace: Loci_Trip_FlightPlace { var p = Loci_Trip_FlightPlace(); p.name = destination.trimmingCharacters(in: .whitespaces); return p }
  var isReady: Bool {
    !origin.trimmingCharacters(in: .whitespaces).isEmpty && !destination.trimmingCharacters(in: .whitespaces).isEmpty
      && !departDate.isEmpty && (returnDate.map { $0 >= departDate } ?? true)
  }

  /// The flight AddFlight saves (the server builds its links again).
  var flight: Loci_Trip_TripFlight {
    var f = Loci_Trip_TripFlight()
    f.origin = originPlace
    f.destination = destinationPlace
    f.departDate = departDate
    if let returnDate { f.returnDate = returnDate }
    f.passengers = Int32(passengers)
    f.cabin = cabin
    return f
  }
}
```

Match `rpc(...)`'s parameter order to the second overload in `APIError+Connect.swift:65`.

- [ ] **Step 2:** Build.
Expected: success.

- [ ] **Step 3:** Commit: `feat(ios): hotel and flight-link reads for the Plan section`.

---

### Task 5: Plan section on the trip page

**Files:**
- Create `Features/Trips/UI/TripPlanSection.swift`.
- Modify `Features/Trips/UI/TripEditorView.swift`.

- [ ] **Step 1: Implement** `TripPlanSection`:

```swift
import LociConnectProto
import SwiftUI

/// The trip's plan: dates, where it sleeps in each city, flights
/// (web: components/trip/TripPlanPanel.tsx). Edits go back to the editor,
/// which sends them with the trip's version and raises the conflict alert.
struct TripPlanSection: View {
  let trip: Loci_Trip_TripDraft
  let onSetDates: (_ start: String, _ end: String) -> Void
  let onSetStay: (Loci_Trip_TripStay) -> Void
  let onAddFlight: (Loci_Trip_TripFlight) -> Void
  let onRemoveFlight: (_ flightID: String) -> Void

  @State private var start = Date()
  @State private var end = Date()
  @State private var stars: [String: Int] = [:]
  @State private var found: [String: [Loci_Favorites_V1_HotelDetails]] = [:]
  @State private var searching: Set<String> = []
  @State private var searched: Set<String> = []
  @State private var search = FlightSearch()
  @State private var links: [Loci_Trip_FlightLink] = []
  @State private var error: String?

  var body: some View {
    Section {
      datesRow
      ForEach(TripPlan.cities(of: trip), id: \.self) { city in stayRow(city) }
      ForEach(trip.flights, id: \.id) { flight in flightRow(flight) }
      flightForm
      if let error { Text(error).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive) }
    } header: {
      Text("Plan").lociCoordStyle(11)
    }
    .onAppear(perform: seedDates)
  }

  private func seedDates() {
    if let s = CalendarMath.parseDateKey(trip.startDate) { start = s }
    if let e = CalendarMath.parseDateKey(trip.endDate) { end = e }
  }

  private var datesRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      DatePicker("Starts", selection: $start, displayedComponents: .date)
      DatePicker("Ends", selection: $end, in: start..., displayedComponents: .date)
      Button("Save dates") { onSetDates(CalendarMath.dateKey(start), CalendarMath.dateKey(end)) }
        .buttonStyle(.borderless)
    }
    .font(.lociBody(15))
  }

  @ViewBuilder private func stayRow(_ city: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(city).font(.lociHeadline(15))
        Spacer()
        if let stay = TripPlan.stay(for: city, in: trip) {
          Text(stay.starRating.isEmpty ? stay.name : "\(stay.name) · \(stay.starRating)★").font(.lociCaption(13))
        } else {
          Text("No hotel yet").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        }
      }
      if let at = TripPlan.coordinate(of: city, in: trip) {
        HStack {
          Picker("Stars", selection: Binding(get: { stars[city] ?? 0 }, set: { stars[city] = $0 })) {
            Text("Any").tag(0)
            Text("3★").tag(3)
            Text("4★").tag(4)
            Text("5★").tag(5)
          }
          .pickerStyle(.segmented)
          Button(searching.contains(city) ? "Searching…" : "Find") { Task { await findHotels(city, at) } }
            .disabled(searching.contains(city))
            .buttonStyle(.borderless)
        }
        ForEach(found[city] ?? [], id: \.id) { hotel in
          Button { pick(hotel, in: city) } label: {
            Text(hotel.starRating.isEmpty ? hotel.name : "\(hotel.name) · \(hotel.starRating)★")
          }
          .buttonStyle(.borderless)
        }
        if searched.contains(city), (found[city] ?? []).isEmpty {
          Text((stars[city] ?? 0) > 0 ? "No \(stars[city]!)★ hotels within 5 km. Try any stars." : "No hotels found within 5 km.")
            .font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
        }
      } else {
        Text("Can't search hotels in \(city): the trip has no map position for it yet.")
          .font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
      }
    }
  }

  private func findHotels(_ city: String, _ at: (latitude: Double, longitude: Double)) async {
    searching.insert(city)
    defer { searching.remove(city) }
    do {
      let hotels = try await TripPlanAPI.hotelsNear(latitude: at.latitude, longitude: at.longitude)
      found[city] = Array(TripPlan.hotels(hotels, stars: stars[city] ?? 0).prefix(5))
      searched.insert(city)
      error = nil
    } catch {
      self.error = "Couldn't look up hotels in \(city) right now."
    }
  }

  private func pick(_ hotel: Loci_Favorites_V1_HotelDetails, in city: String) {
    var stay = Loci_Trip_TripStay()
    stay.cityName = city
    stay.poiID = hotel.id
    stay.name = hotel.name
    if let value = TripPlan.stars(hotel.starRating) { stay.starRating = value == value.rounded() ? String(Int(value)) : String(value) }
    if hotel.website.hasPrefix("https://") { stay.bookingURL = hotel.website }
    found[city] = []
    onSetStay(stay)
  }

  private func flightRow(_ flight: Loci_Trip_TripFlight) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(flight.origin.name) → \(flight.destination.name) · \(flight.departDate)").font(.lociBody(15))
      HStack(spacing: 12) {
        ForEach(flight.links.filter { $0.url.hasPrefix("https://") }, id: \.url) { link in
          if let url = URL(string: link.url) { Link(link.label, destination: url).font(.lociCaption(13)) }
        }
        Spacer()
        Button("Remove", role: .destructive) { onRemoveFlight(flight.id) }.buttonStyle(.borderless).font(.lociCaption(13))
      }
    }
  }

  private var flightForm: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("From (city or airport)", text: $search.origin)
      TextField("To", text: $search.destination)
      DatePicker("Departs", selection: Binding(
        get: { CalendarMath.parseDateKey(search.departDate) ?? start },
        set: { search.departDate = CalendarMath.dateKey($0) }), displayedComponents: .date)
      Stepper("Travellers: \(search.passengers)", value: $search.passengers, in: 1...9)
      HStack {
        Button("Search flights") { Task { await buildLinks() } }.disabled(!search.isReady).buttonStyle(.borderless)
        Spacer()
        if !links.isEmpty {
          Button("Save to trip") { onAddFlight(search.flight); links = [] }.buttonStyle(.borderless)
        }
      }
      ForEach(links.filter { $0.url.hasPrefix("https://") }, id: \.url) { link in
        if let url = URL(string: link.url) { Link(link.label, destination: url).font(.lociCaption(13)) }
      }
      Text("Prices are on the airline sites; Loci only saves your search.")
        .font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
    }
    .font(.lociBody(15))
  }

  private func buildLinks() async {
    do {
      links = try await TripPlanAPI.flightLinks(search)
      error = nil
    } catch {
      self.error = error.message
    }
  }
}
```

Check these against the code before building:
- **`CalendarMath.parseDateKey`'s return type.** If it returns a non-optional or takes a different label, adapt.
- **Return-date toggle.** The form has no return-date field yet. Add a Toggle "Return flight" plus a second DatePicker if time allows; otherwise record it as a deferred minor.

- [ ] **Step 2: Wire it into `TripEditorView`.** Right after the `TripPreferencesSection(...)` line, add:

```swift
          TripPlanSection(
            trip: trip,
            onSetDates: { start, end in Task { await setDates(start, end) } },
            onSetStay: { stay in Task { await setStay(stay) } },
            onAddFlight: { flight in Task { await addFlight(flight) } },
            onRemoveFlight: { id in Task { await removeFlight(id) } }
          )
          .disabled(!canEdit)
```

Then add the edits next to the other edit methods:

```swift
  // MARK: - Plan (dates, stays, flights)

  private func setDates(_ start: String, _ end: String) async {
    guard let trip else { return }
    var request = Loci_Trip_SetTripDatesRequest()
    request.tripID = trip.id
    request.startDate = start
    request.endDate = end
    request.baseVersion = trip.version
    await apply("Could not save the dates.", request) { await TripAPI.client.setTripDates(request: $0, headers: [:]) }
  }

  private func setStay(_ stay: Loci_Trip_TripStay) async {
    guard let trip else { return }
    var request = Loci_Trip_SetStayRequest()
    request.tripID = trip.id
    request.stay = stay
    request.baseVersion = trip.version
    await apply("Could not save the hotel.", request) { await TripAPI.client.setStay(request: $0, headers: [:]) }
  }

  private func addFlight(_ flight: Loci_Trip_TripFlight) async {
    guard let trip else { return }
    var request = Loci_Trip_AddFlightRequest()
    request.tripID = trip.id
    request.flight = flight
    request.baseVersion = trip.version
    await apply("Could not save the flight.", request) { await TripAPI.client.addFlight(request: $0, headers: [:]) }
  }

  private func removeFlight(_ id: String) async {
    guard let trip else { return }
    var request = Loci_Trip_RemoveFlightRequest()
    request.tripID = trip.id
    request.flightID = id
    request.baseVersion = trip.version
    await apply("Could not remove the flight.", request) { await TripAPI.client.removeFlight(request: $0, headers: [:]) }
  }
```

- [ ] **Step 3:** Build and run `lociTests`.
Expected: success.
- [ ] **Step 4:** Lint with `scripts/format.sh --lint-only`. Format only the touched files.
- [ ] **Step 5:** Commit: `feat(ios): Plan section — dates, a stay per city by stars, flight searches`.

---

### Task 6: The planner sheet

**Files:**
- Create `Features/Trips/UI/TripPlannerSheet.swift` and `Features/Trips/UI/TripActionCardView.swift`.
- Modify `TripEditorView.swift`: add the toolbar button and the sheet.

- [ ] **Step 1: Implement** `TripActionCardView`:

```swift
import LociConnectProto
import SwiftUI

/// One change the planner proposes (web: components/chat/TripActionCard.tsx).
struct TripActionCardView: View {
  let proposal: Loci_Chat_ActionProposal
  let state: TripActionsModel.CardState
  let canApply: Bool
  let onApply: (_ option: Int?) -> Void
  let onDismiss: () -> Void

  private var isHotels: Bool { if case .searchHotels = proposal.action.kind { true } else { false } }
  private var isFlight: Bool { if case .searchFlights = proposal.action.kind { true } else { false } }
  private var busy: Bool { state == .applying }

  var body: some View {
    MuseBubble(role: .agent) {
      VStack(alignment: .leading, spacing: 10) {
        Text(proposal.summary).font(.museBody)
        if isHotels {
          ForEach(Array(proposal.options.enumerated()), id: \.offset) { index, option in
            Button { onApply(index) } label: {
              VStack(alignment: .leading) {
                Text(option.label)
                if !option.detail.isEmpty { Text(option.detail).font(.lociCaption(12)).foregroundStyle(Color.museTextSecondary) }
              }
            }
            .buttonStyle(MusePillButtonStyle())
            .disabled(busy || !canApply)
          }
        }
        if isFlight, case .flight(let flight)? = proposal.options.first?.choice {
          ForEach(flight.links.filter { $0.url.hasPrefix("https://") }, id: \.url) { link in
            if let url = URL(string: link.url) { Link(link.label, destination: url) }
          }
        }
        if case .failed(let text) = state {
          Text(text).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive)
        }
        HStack {
          if !isHotels, !isFlight || !proposal.options.isEmpty {
            Button(canApply ? (busy ? "Updating…" : (isFlight ? "Save to trip" : "Confirm")) : "Loading trip…") {
              onApply(isFlight ? 0 : nil)
            }
            .buttonStyle(MusePillButtonStyle())
            .disabled(busy || !canApply)
          }
          Button("Not now", action: onDismiss).buttonStyle(MusePillButtonStyle()).disabled(busy)
        }
      }
    }
  }
}
```

Check two names against the generated Swift:
- **The oneof:** `proposal.action.kind`'s case names (`.searchHotels(_)`, `.searchFlights(_)`) and the `ActionOption.choice` case `.flight(_)`.
- **The style:** `MusePillButtonStyle`'s initialiser in `MuseChatHeader.swift:165`.

`TripPlannerSheet`:

```swift
import LociConnectProto
import SwiftUI

/// "Ask the planner": a chat about this trip whose turns propose changes as
/// cards (the agent never changes the trip without a tap). A turn that is a
/// normal answer instead offers to open it.
struct TripPlannerSheet: View {
  let trip: Loci_Trip_TripDraft
  /// The trip's version now, for the card's base_version; nil while loading.
  let currentVersion: () -> Int64?
  let onTripChanged: (Loci_Trip_TripDraft) -> Void
  let onReloadTrip: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var message = ""
  @State private var actions = TripActionsModel()
  private var controller: SearchSessionController { .shared }

  private var proposals: [Loci_Chat_ActionProposal] {
    (controller.state?.proposals ?? []).filter { actions.state($0.id) != .applied && actions.state($0.id) != .dismissed }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Text("Ask for dates, hotels, more days or flights for \(trip.title).")
            .font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
          ForEach(proposals, id: \.id) { proposal in
            TripActionCardView(
              proposal: proposal,
              state: actions.state(proposal.id),
              canApply: currentVersion() != nil,
              onApply: { option in Task { await apply(proposal, option) } },
              onDismiss: { Task { await actions.dismiss(proposal) } }
            )
          }
          if controller.state?.status == .streaming { ProgressView() }
          if let link = controller.startedLink {
            Button("See the answer") { dismiss(); AppRouter.shared.open(link) }
              .buttonStyle(MusePillButtonStyle())
          }
        }
        .padding(LociTheme.defaultPadding)
      }
      .safeAreaInset(edge: .bottom) { composer }
      .navigationTitle("Planner")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
  }

  private var composer: some View {
    HStack {
      TextField("12 to 15 Nov, 4-star hotels…", text: $message, axis: .vertical)
        .textFieldStyle(.roundedBorder)
      Button("Send") { Task { await send() } }
        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.state?.status == .streaming)
    }
    .padding(LociTheme.defaultPadding)
    .background(Color.lociPaper)
  }

  private func send() async {
    let text = message
    message = ""
    try? await controller.start(query: text, cityName: trip.cityName, tripId: trip.id)
  }

  private func apply(_ proposal: Loci_Chat_ActionProposal, _ option: Int?) async {
    if let next = await actions.apply(proposal, option: option, baseVersion: currentVersion()) {
      onTripChanged(next)
    } else if actions.needsReload {
      await onReloadTrip()
      actions.reloaded()
    }
  }
}
```

Check two things against the code:
- **`SearchState.status`'s streaming case name, and `AppRouter.shared.open(_: SessionLink)`.** Match the real API.
- **`controller.start` throwing.** If it throws `StartError.noDefaultProfile`, show the error message instead of `try?`.

- [ ] **Step 2: Wire it into `TripEditorView`.**
  - Add `@State private var planning = false`.
  - In the existing `.toolbar { … }`, add a `ToolbarItem(placement: .primaryAction) { Button { planning = true } label: { Label("Ask the planner", systemImage: "bubble.left.and.text.bubble.right") } }`. Show it only when `canEdit && !isOffline`.
  - Add:

    ```swift
    .sheet(isPresented: $planning) {
      if let trip {
        TripPlannerSheet(
          trip: trip,
          currentVersion: { self.trip?.version },
          onTripChanged: { next in Task { await adopt(next) } },
          onReloadTrip: { await reload() }
        )
      }
    }
    ```

- [ ] **Step 3:** Build, test and lint.
Expected: success.
- [ ] **Step 4:** Commit: `feat(ios): ask the planner from a trip — proposals as cards`.

---

### Task 7: Ship

- [ ] **Step 1:** Run `fastlane test`, or the xcodebuild test command, plus `scripts/format.sh --lint-only`.
Expected: green.
- [ ] **Step 2:** Final review, then PR (`feat(ios): plan a trip — Plan section and planner proposals`), CI green, merge.
- [ ] **Step 3:** The nightly TestFlight (02:00 UTC) ships it. Dispatch `release.yml` with `lane: beta` only if the owner asks.
- [ ] **Step 4:** Device QA, owed by the owner:
  1. Open a trip.
  2. Set dates.
  3. Find 4★ hotels and pick one.
  4. Search flights and save one.
  5. Ask the planner "12 to 15 November, 4-star hotels" and confirm the cards.
- [ ] **Step 5:** Clean up: `rm -rf /private/tmp/ios-trip-dd /private/tmp/loci-connect-proto`, and remove the worktree.

---

## Spec deviations (deliberate)

- **A planner sheet, not cards in the Assistant thread.** A proposal-only turn has no `start` event, so the results screen never opens for it.
- **Applying from the sheet uses the editor's live trip version.** A stale one triggers a reload, so the next tap works.
- **No return-date field in the flight form** unless time allows (Task 5 note). The server and web support it.
