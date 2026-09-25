import CoreLocation
import Foundation
import LociConnectProto
import Testing

@testable import loci

private func poi(_ name: String, _ lat: Double, _ lon: Double, id: String = "") -> Loci_Poi_POIDetailedInfo {
  var poi = Loci_Poi_POIDetailedInfo()
  poi.id = id.isEmpty ? name : id
  poi.name = name
  poi.latitude = lat
  poi.longitude = lon
  return poi
}

private func tripStop(_ name: String, _ lat: Double?, _ lon: Double?) -> Loci_Trip_TripStop {
  var stop = Loci_Trip_TripStop()
  stop.id = "s-\(name)"
  stop.name = name
  if let lat, let lon { stop.poi = poi(name, lat, lon) }
  return stop
}

struct WalkDayTests {
  @Test func tripDayKeepsOrderAndSkipsStopsWithoutALocation() {
    var trip = Loci_Trip_TripDraft()
    trip.id = "t1"
    trip.cityName = "Lisbon"
    var day = Loci_Trip_TripDay()
    day.id = "d2"
    day.dayNumber = 2
    day.cityName = "Sintra"
    day.stops = [tripStop("Pena", 38.7876, -9.3906), tripStop("No pin", nil, nil), tripStop("Null Island", 0, 0), tripStop("Quinta", 38.7963, -9.3960)]

    let walk = WalkDay.from(trip: trip, day: day)

    #expect(walk.id == "trip:t1:d2")
    #expect(walk.title == "Day 2 · Sintra")
    #expect(walk.stops.map(\.name) == ["Pena", "Quinta"])
    #expect(walk.withoutLocation == 2)
    #expect(walk.stops[0].coordinate.latitude == 38.7876)
  }

  @Test func tripDayInTheTripsOwnCityHasNoCitySuffix() {
    var trip = Loci_Trip_TripDraft()
    trip.id = "t1"
    trip.cityName = "Lisbon"
    var day = Loci_Trip_TripDay()
    day.id = "d1"
    day.dayNumber = 1
    day.cityName = "Lisbon"
    #expect(WalkDay.from(trip: trip, day: day).title == "Day 1")
  }

  @Test func dayGroupBecomesAWalkDay() {
    let group = DayGroup(number: 2, stops: [poi("A", 41.14, -8.61), poi("B", 0, 0), poi("C", 41.15, -8.62)])
    let walk = WalkDay.from(group: group, sessionId: "s9", cityName: "Porto")
    #expect(walk.id == "session:s9:2")
    #expect(walk.title == "Day 2 · Porto")
    #expect(walk.stops.map(\.name) == ["A", "C"])
    #expect(walk.withoutLocation == 1)
  }
}

struct WalkCardTests {
  @Test func routeTextLeadsWithTheStopProgress() {
    let state = NearbyWalkAttributes.ContentState(
      steps: 1,
      distanceMeters: 1,
      placesNearby: 0,
      destinationName: "Café X",
      destinationMeters: 400,
      etaSeconds: 300,
      stopProgress: "3 of 6"
    )
    #expect(state.routeText == "3 of 6 · Café X · 400 m · 5 min")
    #expect(NearbyWalkAttributes.ContentState(steps: 0, distanceMeters: 0, placesNearby: 0).routeText == nil)
  }

  @Test func olderPayloadsStillDecode() throws {
    let state = #"{"steps":3,"distanceMeters":2,"placesNearby":1}"#
    let decoded = try JSONDecoder().decode(NearbyWalkAttributes.ContentState.self, from: Data(state.utf8))
    #expect(decoded.stopProgress == nil)
    let attributes = #"{"startedAt":0,"radiusKm":5}"#
    #expect(try JSONDecoder().decode(NearbyWalkAttributes.self, from: Data(attributes.utf8)).title == nil)
  }
}
