import CoreLocation
import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

/// Places I've been and the visits that feed it: a walk arrival carries its
/// trip, "I've been here" records a manual visit, and the screen groups visits
/// by city (web: lib/visited/group.ts, lib/api/travel-history.ts).
struct VisitedPlacesTests {
  @Test func walkDayTripIDParsesTripPrefix() {
    let trip = WalkDay(id: "trip:abc-123:day-1", title: "Day 1", stops: [], withoutLocation: 0)
    let session = WalkDay(id: "session:xyz:1", title: "Day 1", stops: [], withoutLocation: 0)
    #expect(trip.tripID == "abc-123")
    #expect(session.tripID == nil)
  }

  @Test func visitRequestCarriesTripAndDeviceFix() {
    let visit = SpotVisit(poiID: "poi-1", poiName: "Sé", cityName: "Lisbon", latitude: 38.71, longitude: -9.13, tripID: "trip-9")
    let location = CLLocation(latitude: 38.7101, longitude: -9.1302)
    let request = ProgressAPI.visitRequest(visit, at: location)
    #expect(request.tripID == "trip-9")
    #expect(request.poiID == "poi-1")
    #expect(request.hasDeviceLocation)
  }

  @Test func visitRequestWithoutTripLeavesItEmpty() {
    let visit = SpotVisit(poiID: "poi-1", poiName: "Sé", cityName: "Lisbon", latitude: 38.71, longitude: -9.13)
    #expect(ProgressAPI.visitRequest(visit, at: CLLocation(latitude: 38.71, longitude: -9.13)).tripID.isEmpty)
  }

  @Test func manualVisitHasNoDeviceFixSoEarnsNoPoints() throws {
    var poi = Loci_Poi_POIDetailedInfo()
    poi.id = "poi-1"
    poi.name = "Miradouro"
    poi.latitude = 38.71
    poi.longitude = -9.14
    let request = try #require(TravelHistoryAPI.manualVisitRequest(poi: poi, cityName: " Lisbon "))
    #expect(request.cityName == "Lisbon")
    #expect(request.poiID == "poi-1")
    #expect(!request.hasDeviceLocation)
  }

  @Test func manualVisitRefusesAPlaceTheServerWouldReject() {
    var poi = Loci_Poi_POIDetailedInfo()
    poi.id = "poi-1"
    poi.latitude = 38.71
    poi.longitude = -9.14
    #expect(TravelHistoryAPI.manualVisitRequest(poi: poi, cityName: "") == nil)
    poi.latitude = 0
    poi.longitude = 0
    #expect(TravelHistoryAPI.manualVisitRequest(poi: poi, cityName: "Lisbon") == nil)
  }
}

@MainActor struct VisitedPlacesStoreTests {
  private static func visit(_ name: String, _ city: String, day: Int) -> Loci_Travelhistory_VisitedPOI {
    var poi = Loci_Travelhistory_VisitedPOI()
    poi.id = "\(name)-id"
    poi.poiName = name
    poi.cityName = city
    poi.visitedAt = Google_Protobuf_Timestamp(date: Date(timeIntervalSince1970: TimeInterval(day) * 86_400))
    return poi
  }

  private final class Paged: VisitedPlacesService, @unchecked Sendable {
    let pages: [[Loci_Travelhistory_VisitedPOI]]
    let total: Int32
    private(set) var requested: [Int32] = []

    init(pages: [[Loci_Travelhistory_VisitedPOI]], total: Int32) {
      self.pages = pages
      self.total = total
    }

    var failDeletes = false
    private(set) var deleted: [String] = []

    func visitedPOIs(page: Int32) async throws -> (pois: [Loci_Travelhistory_VisitedPOI], total: Int32) {
      requested.append(page)
      let index = Int(page) - 1
      return (pages.indices.contains(index) ? pages[index] : [], total)
    }

    func deleteVisitedPOI(id: String) async throws -> Bool {
      if failDeletes { throw APIError.custom("Could not remove it.") }
      deleted.append(id)
      return true
    }
  }

  @Test func deleteRemovesTheRowAndTellsTheServer() async {
    let service = Paged(pages: [[Self.visit("A", "Lisbon", day: 1), Self.visit("B", "Lisbon", day: 2)]], total: 2)
    let store = VisitedPlacesStore(service: service)
    await store.load()
    await store.delete("A-id")
    #expect(store.visits.map(\.poiName) == ["B"])
    #expect(store.total == 1)
    #expect(service.deleted == ["A-id"])
  }

  @Test func deleteRestoresRowOnFailure() async {
    let service = Paged(pages: [[Self.visit("A", "Lisbon", day: 1)]], total: 1)
    service.failDeletes = true
    let store = VisitedPlacesStore(service: service)
    await store.load()
    await store.delete("A-id")
    #expect(store.visits.map(\.poiName) == ["A"])
    #expect(store.total == 1)
    #expect(store.error == "Could not remove it.")
  }

  @Test func groupsByCityNewestFirst() async {
    let visits = [Self.visit("Sé", "Lisbon", day: 1), Self.visit("Ribeira", "Porto", day: 5), Self.visit("Belém", "Lisbon", day: 3)]
    let service = Paged(pages: [visits], total: 3)
    let store = VisitedPlacesStore(service: service)
    await store.load()
    #expect(store.grouped.map(\.city) == ["Porto", "Lisbon"])
    #expect(store.grouped.last?.places.map(\.poiName) == ["Belém", "Sé"])
  }

  @Test func loadMoreStopsAtTotal() async {
    let service = Paged(pages: [[Self.visit("A", "Lisbon", day: 1)], [Self.visit("B", "Lisbon", day: 2)]], total: 2)
    let store = VisitedPlacesStore(service: service)
    await store.load()
    #expect(store.canLoadMore)
    await store.loadMore()
    #expect(!store.canLoadMore)
    await store.loadMore()
    #expect(service.requested == [1, 2])
  }
}
