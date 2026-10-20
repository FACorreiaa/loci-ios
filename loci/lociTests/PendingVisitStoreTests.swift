import CoreLocation
import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

/// Records what would be sent, and fails on request.
nonisolated final class StubVisitRecorder: VisitRecorder, @unchecked Sendable {
  private let lock = NSLock()
  private var _sent: [Loci_Travelhistory_RecordVisitRequest] = []
  var sent: [Loci_Travelhistory_RecordVisitRequest] { lock.withLock { _sent } }
  var fails = false

  func record(_ request: Loci_Travelhistory_RecordVisitRequest) async throws {
    if fails { throw APIError.server("down") }
    lock.withLock { _sent.append(request) }
  }
}

struct VisitMatchTests {
  // Praça do Comércio, and places around it.
  private let here = CLLocationCoordinate2D(latitude: 38.7077, longitude: -9.1365)

  private func place(_ id: String, metresNorth: Double) -> VisitCandidate {
    // ~111,320 m per degree of latitude.
    VisitCandidate(poiID: id, name: id, cityName: "Lisbon", latitude: 38.7077 + metresNorth / 111_320, longitude: -9.1365)
  }

  @Test func nearestWithinRadius() {
    let match = VisitMatch.nearest(to: here, stops: [place("far", metresNorth: 60), place("near", metresNorth: 20)], favorites: [])
    #expect(match?.poiID == "near")
  }

  @Test func beyondRadiusIsNil() {
    #expect(VisitMatch.nearest(to: here, stops: [place("a", metresNorth: 90)], favorites: [place("b", metresNorth: 120)]) == nil)
  }

  @Test func stopsComeBeforeSavedPlaces() {
    let match = VisitMatch.nearest(to: here, stops: [place("stop", metresNorth: 70)], favorites: [place("saved", metresNorth: 5)])
    #expect(match?.poiID == "stop")
    #expect(VisitMatch.nearest(to: here, stops: [place("stop", metresNorth: 200)], favorites: [place("saved", metresNorth: 5)])?.poiID == "saved")
  }

  @Test func favoritesInTheCityWithCoordinatesOnly() {
    func item(_ id: String, city: String, type: Loci_Favorites_V1_ContentType = .poi, lat: Double = 38.7, lon: Double = -9.1) -> Loci_Favorites_V1_FavoriteItem {
      var item = Loci_Favorites_V1_FavoriteItem()
      item.itemID = id
      item.cityName = city
      item.contentType = type
      item.latitude = lat
      item.longitude = lon
      return item
    }
    let saved = [
      item("a", city: "lisbon"),
      item("b", city: "Porto"),
      item("c", city: "Lisbon", type: .itinerary),
      item("d", city: "Lisbon", lat: 0, lon: 0),
    ]
    #expect(VisitMatch.candidates(favorites: saved, city: "Lisbon").map(\.poiID) == ["a"])
  }
}

@Suite(.serialized) struct PendingVisitStoreTests {
  private func store() -> PendingVisitStore {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    return PendingVisitStore(defaults: UserDefaults(suiteName: "pending-visits-\(UUID().uuidString)") ?? .standard, calendar: utc)
  }

  private let arrival = Date(timeIntervalSince1970: 1_792_486_800) // 2026-10-20 09:00 UTC

  private func visit(_ id: String, poi: String = "belem", at date: Date? = nil) -> PendingVisit {
    PendingVisit(
      id: id,
      place: VisitCandidate(poiID: poi, name: "Belém", cityName: "Lisbon", latitude: 38.6916, longitude: -9.2160),
      tripID: "t1",
      arrival: date ?? arrival,
      latitude: 38.6917,
      longitude: -9.2161,
      accuracy: 30,
    )
  }

  @Test func samePlaceSameDayIsKeptOnce() {
    let store = store()
    #expect(store.add(visit("1"), now: arrival))
    #expect(!store.add(visit("2", at: arrival.addingTimeInterval(3600)), now: arrival))
    #expect(store.add(visit("3", at: arrival.addingTimeInterval(86_400)), now: arrival))
    #expect(store.add(visit("4", poi: "alfama"), now: arrival))
    #expect(store.visits(tripID: "t1", now: arrival).map(\.id) == ["1", "4", "3"])
  }

  @Test func confirmSendsAnOnTheSpotVisitAtArrival() async throws {
    let store = store()
    store.add(visit("1"), now: arrival)
    let recorder = StubVisitRecorder()
    try await store.confirm(id: "1", recorder: recorder)
    let request = try #require(recorder.sent.first)
    #expect(request.source == .visitEvent)
    #expect(request.tripID == "t1")
    #expect(request.poiID == "belem")
    #expect(request.visitedAt.date == arrival)
    #expect(request.deviceLocation.latitude == 38.6917)
    #expect(store.all(now: arrival).isEmpty)
  }

  @Test func failedConfirmKeepsTheVisit() async {
    let store = store()
    store.add(visit("1"), now: arrival)
    let recorder = StubVisitRecorder()
    recorder.fails = true
    await #expect(throws: (any Error).self) { try await store.confirm(id: "1", recorder: recorder) }
    #expect(store.all(now: arrival).map(\.id) == ["1"])
  }

  @Test func aWeekUnansweredDrops() {
    let store = store()
    store.add(visit("1"), now: arrival)
    #expect(store.all(now: arrival.addingTimeInterval(6 * 86_400)).count == 1)
    #expect(store.all(now: arrival.addingTimeInterval(8 * 86_400)).isEmpty)
  }

  @Test func dismissForgets() {
    let store = store()
    store.add(visit("1"), now: arrival)
    store.dismiss(id: "1")
    #expect(store.all(now: arrival).isEmpty)
  }
}

struct VisitLoggerGateTests {
  private func today() -> TodayFirst { TodayFirst(trip: Loci_Trip_TripDraft(), day: Loci_Trip_TripDay(), next: nil) }

  @Test func visitLoggerOffOutsideTripDay() {
    #expect(VisitLogger.shouldRun(enabled: true, authorization: .authorizedAlways, today: today()))
    #expect(!VisitLogger.shouldRun(enabled: true, authorization: .authorizedAlways, today: nil))
    #expect(!VisitLogger.shouldRun(enabled: false, authorization: .authorizedAlways, today: today()))
    #expect(!VisitLogger.shouldRun(enabled: true, authorization: .authorizedWhenInUse, today: today()))
  }
}
