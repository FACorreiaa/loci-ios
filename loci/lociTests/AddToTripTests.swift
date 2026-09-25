import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

/// Add to trip (parity pass 2, Phase 3c): the stop built from a place, the
/// requests, the stale-version retry, and the trip id COMPLETE carries.
struct AddToTripTests {
  private let poiID = "5c7e0000-0000-4000-8000-000000000001"
  private let cityID = "c1770000-0000-4000-8000-000000000001"

  private func place(id: String = "5c7e0000-0000-4000-8000-000000000001", name: String = "Miradouro da Graça") -> Loci_Poi_POIDetailedInfo {
    var poi = Loci_Poi_POIDetailedInfo()
    poi.id = id
    poi.name = name
    poi.description_p = "A lookout."
    return poi
  }

  private func trip(version: Int64 = 3, stopsOnDay2: Int = 2) -> Loci_Trip_TripDraft {
    var trip = Loci_Trip_TripDraft()
    trip.id = "trip-1"
    trip.cityName = "Lisbon"
    trip.title = "Lisbon"
    trip.version = version
    trip.days = (1...2).map { number in
      var day = Loci_Trip_TripDay()
      day.id = "day-\(number)-v\(version)"
      day.dayNumber = Int32(number)
      day.stops = Array(repeating: Loci_Trip_TripStop(), count: number == 2 ? stopsOnDay2 : 0)
      return day
    }
    return trip
  }

  // MARK: - TripStopBuilder

  @Test func storedPlaceKeepsItsPoiID() {
    let stop = TripStopBuilder.stop(from: place(), orderIndex: 2, id: "s1")
    #expect(stop.id == "s1")
    #expect(stop.poiID == poiID)
    #expect(stop.orderIndex == 2)
    #expect(stop.name == "Miradouro da Graça")
    #expect(!stop.hasRecommendationTrace)
  }

  @Test func nameKeyedPlaceGoesInByNameOnly() {
    let stop = TripStopBuilder.stop(from: place(id: "Miradouro da Graça|38.7|-9.1"), orderIndex: 0)
    #expect(stop.poiID.isEmpty)
    #expect(stop.name == "Miradouro da Graça")
    #expect(UUID(uuidString: stop.id) != nil)
  }

  @Test func notesPreferRationaleThenDescriptionThenFallback() {
    var poi = place()
    poi.descriptionPoi = "  Best at sunset.  "
    #expect(TripStopBuilder.notes(for: poi) == "Best at sunset.")
    poi.recommendationRationale = "You like viewpoints."
    #expect(TripStopBuilder.notes(for: poi) == "You like viewpoints.")
    var bare = Loci_Poi_POIDetailedInfo()
    bare.name = "X"
    #expect(TripStopBuilder.notes(for: bare) == "Added from Loci")
    #expect(TripStopBuilder.notes(for: place()) == "A lookout.")
  }

  @Test func fieldsFitTheProtoLimits() {
    var poi = place(name: String(repeating: "a", count: 400))
    poi.description_p = String(repeating: "b", count: 5000)
    let stop = TripStopBuilder.stop(from: poi, orderIndex: -1)
    #expect(stop.name.count == 300)
    #expect(stop.notes.count == 4000)
    #expect(stop.orderIndex == 0)
    #expect(TripStopBuilder.name(for: place(name: "   ")) == "Saved place")
  }

  @Test func traceRidesAlong() {
    var poi = place()
    poi.recommendationTrace.runID = "run-1"
    let stop = TripStopBuilder.stop(from: poi, orderIndex: 0)
    #expect(stop.hasRecommendationTrace)
    #expect(stop.recommendationTrace.runID == "run-1")
  }

  // MARK: - Requests

  @Test func listTripsAsksForTheFirstFifty() {
    let request = AddToTripPayload.listTrips()
    #expect(request.pagination.page == 1)
    #expect(request.pagination.pageSize == 50)
  }

  @Test func addStopUsesTheFreshVersionAndTheDaysCurrentID() throws {
    let request = try #require(AddToTripPayload.addStop(to: trip(version: 7), dayNumber: 2, poi: place(), stopID: "s1"))
    #expect(request.tripID == "trip-1")
    #expect(request.dayID == "day-2-v7")
    #expect(request.baseVersion == 7)
    #expect(request.stop.orderIndex == 2)
    #expect(request.stop.id == "s1")
    #expect(AddToTripPayload.addStop(to: trip(), dayNumber: 5, poi: place()) == nil)
  }

  @Test func newTripHasTheCityOneDayAndThePlace() {
    var poi = place()
    poi.cityID = cityID
    let request = AddToTripPayload.newTrip(for: poi, cityName: " Lisbon ", userID: nil)
    #expect(request.baseVersion == 0)
    #expect(request.trip.userID == "self")
    #expect(request.trip.cityName == "Lisbon")
    #expect(request.trip.cityID == cityID)
    #expect(request.trip.title == "Lisbon trip")
    #expect(request.trip.days.count == 1)
    #expect(request.trip.days[0].dayNumber == 1)
    #expect(request.trip.days[0].stops.map(\.poiID) == [poiID])
    #expect(AddToTripPayload.newTrip(for: place(), cityName: "", userID: "u1").trip.title == "My trip")
    #expect(AddToTripPayload.newTrip(for: place(), cityName: "", userID: "u1").trip.userID == "u1")
    #expect(!AddToTripPayload.newTrip(for: place(), cityName: "Porto", userID: nil).trip.hasCityID)
  }

  @Test func dayLabelShowsDateInUTCAndAnotherCity() {
    var day = Loci_Trip_TripDay()
    day.dayNumber = 2
    #expect(AddToTripPayload.dayLabel(day) == "Day 2")
    day.date = Google_Protobuf_Timestamp(date: Date(timeIntervalSince1970: 1_790_985_600))  // Sat 3 Oct 2026, UTC
    day.cityName = "Sintra"
    #expect(AddToTripPayload.dayLabel(day, tripCity: "Lisbon", locale: Locale(identifier: "en_GB")) == "Day 2 · Sat 3 Oct · Sintra")
    day.cityName = "lisbon"
    #expect(AddToTripPayload.dayLabel(day, tripCity: "Lisbon", locale: Locale(identifier: "en_GB")) == "Day 2 · Sat 3 Oct")
  }

  // MARK: - Stale-version retry

  @Test func addReadsTheTripFirst() async throws {
    let service = ScriptedTripService(reads: [trip(version: 9)], adds: [.success])
    let added = try await AddToTripFlow.add(place(), tripID: "trip-1", dayNumber: 2, service: service)
    #expect(added.dayNumber == 2)
    #expect(service.sentVersions == [9])
    #expect(service.readCount == 1)
  }

  @Test func staleVersionRereadsAndRetriesOnce() async throws {
    // Another device saved in between: new version, new day ids.
    let service = ScriptedTripService(reads: [trip(version: 3), trip(version: 4, stopsOnDay2: 3)], adds: [.stale, .success])
    let added = try await AddToTripFlow.add(place(), tripID: "trip-1", dayNumber: 2, service: service)
    #expect(added.dayNumber == 2)
    #expect(service.sentVersions == [3, 4])
    #expect(service.sentDayIDs == ["day-2-v3", "day-2-v4"])
    #expect(service.sentOrderIndexes == [2, 3])
  }

  @Test func secondStaleVersionGivesUp() async {
    let service = ScriptedTripService(reads: [trip(version: 3), trip(version: 4)], adds: [.stale, .stale])
    await #expect(throws: AddToTripError.staleVersion) {
      try await AddToTripFlow.add(place(), tripID: "trip-1", dayNumber: 2, service: service)
    }
    #expect(service.sentVersions.count == 2)
  }

  @Test func aMissingDayIsNotRetried() async {
    let service = ScriptedTripService(reads: [trip()], adds: [])
    await #expect(throws: AddToTripError.dayMissing) {
      try await AddToTripFlow.add(place(), tripID: "trip-1", dayNumber: 9, service: service)
    }
    #expect(service.sentVersions.isEmpty)
  }

  @Test func twoAddsInARowBothLand() async throws {
    // The preview service bumps the version and renames days as the server does.
    let service = PreviewAddToTripService(trips: [trip(version: 1)])
    _ = try await AddToTripFlow.add(place(), tripID: "trip-1", dayNumber: 2, service: service)
    let second = try await AddToTripFlow.add(place(), tripID: "trip-1", dayNumber: 2, service: service)
    #expect(second.trip.version == 3)
    #expect(second.trip.days[1].stops.count == 4)
  }

  // MARK: - Store

  @MainActor @Test func storePicksTheFirstTripAndDayAndKeepsTheDayAcrossAdds() async {
    let store = AddToTripStore(poi: place(), cityName: "Lisbon", service: PreviewAddToTripService(trips: [trip(version: 1)]))
    await store.load()
    #expect(store.selectedTripID == "trip-1")
    #expect(store.selectedDayNumber == 1)
    store.selectedDayNumber = 2
    #expect(await store.add())
    #expect(store.added?.dayNumber == 2)
    #expect(store.canAdd)
    #expect(store.selectedTrip?.days[1].stops.count == 3)
  }

  @MainActor @Test func storeCreatesATripWhenThereAreNone() async {
    let store = AddToTripStore(poi: place(), cityName: "Lisbon", service: PreviewAddToTripService(trips: []))
    await store.load()
    #expect(store.trips.isEmpty)
    #expect(await store.createTrip(userID: nil))
    #expect(store.added?.dayNumber == 1)
    #expect(store.trips.first?.title == "Lisbon trip")
  }

  // MARK: - Edit trip CTA

  @Test func tripIDFromNavigationPrefersTheQuery() {
    var navigation = Loci_Chat_NavigationData()
    navigation.url = "/trips/from-url?x=1"
    #expect(SearchState.tripID(from: navigation) == "from-url")
    navigation.queryParams = ["tripId": "from-query"]
    #expect(SearchState.tripID(from: navigation) == "from-query")
    navigation = Loci_Chat_NavigationData()
    navigation.url = "/itinerary?sessionId=s1"
    #expect(SearchState.tripID(from: navigation) == nil)
  }

  @Test func completeWithNavigationRemembersTheTrip() {
    var state = SearchState()
    state.apply(Events.start("s1", domain: .itinerary, city: "Rome"))
    var complete = Events.complete("s1", id: "e2")
    complete.navigation.url = "/trips/t9"
    complete.navigation.routeType = "trip"
    state.apply(complete)
    #expect(state.savedTripID == "t9")
    var plain = SearchState()
    plain.apply(Events.complete("s1", id: "e2"))
    #expect(plain.savedTripID == nil)
  }
}

/// Reads and adds in the order a test scripts them.
private final class ScriptedTripService: AddToTripService, @unchecked Sendable {
  enum Add { case success, stale }

  private let lock = NSLock()
  private var reads: [Loci_Trip_TripDraft]
  private var adds: [Add]
  private(set) var readCount = 0
  private(set) var sentVersions: [Int64] = []
  private(set) var sentDayIDs: [String] = []
  private(set) var sentOrderIndexes: [Int32] = []

  init(reads: [Loci_Trip_TripDraft], adds: [Add]) {
    self.reads = reads
    self.adds = adds
  }

  func trips() async throws -> [Loci_Trip_TripDraft] { [] }

  func trip(id: String) async throws -> Loci_Trip_TripDraft {
    lock.withLock {
      readCount += 1
      return reads.count > 1 ? reads.removeFirst() : reads[0]
    }
  }

  func addStop(_ request: Loci_Trip_AddStopRequest) async throws -> Loci_Trip_TripDraft {
    let next: Add = lock.withLock {
      sentVersions.append(request.baseVersion)
      sentDayIDs.append(request.dayID)
      sentOrderIndexes.append(request.stop.orderIndex)
      return adds.removeFirst()
    }
    if next == .stale { throw AddToTripError.staleVersion }
    var draft = Loci_Trip_TripDraft()
    draft.id = request.tripID
    draft.version = request.baseVersion + 1
    return draft
  }

  func createTrip(_ request: Loci_Trip_SaveTripRequest) async throws -> Loci_Trip_TripDraft { request.trip }
}
