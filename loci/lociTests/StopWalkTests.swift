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
    day.stops = [
      tripStop("Pena", 38.7876, -9.3906),
      tripStop("No pin", nil, nil),
      tripStop("Null Island", 0, 0),
      tripStop("Quinta", 38.7963, -9.3960),
    ]

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

private func at(_ lat: Double, _ lon: Double) -> CLLocation {
  CLLocation(
    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
    altitude: 0,
    horizontalAccuracy: 5,
    verticalAccuracy: 5,
    timestamp: Date()
  )
}

private func stop(_ name: String, _ lat: Double, _ lon: Double) -> WalkStop {
  WalkStop(id: name, name: name, poi: poi(name, lat, lon), coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
}

/// Porto, three stops ~200 m apart going north.
private let porto = WalkDay(
  id: "trip:t:d",
  title: "Day 1",
  stops: [stop("A", 41.1480, -8.6100), stop("B", 41.1498, -8.6100), stop("C", 41.1516, -8.6100)],
  withoutLocation: 0
)
private let origin = CLLocationCoordinate2D(latitude: 41.1460, longitude: -8.6100)

@MainActor struct StopWalkTests {
  /// Straight two-point routes, so arrival is purely geometric.
  private func walk() -> StopWalk {
    let navigator = WalkNavigator(directions: { from, to in
      WalkNavigator.Leg(coordinates: [from, to], meters: WalkingRoute.distance(from, to), expectedTravelTime: 120)
    })
    return StopWalk(navigator: navigator, live: false)
  }

  @Test func startsWalkingToTheFirstStop() async {
    let walk = walk()
    await walk.start(porto, from: origin)
    #expect(walk.phase == .walking)
    #expect(walk.index == 0)
    #expect(walk.navigator.isNavigating)
    #expect(walk.navigator.destination?.name == "A")
    #expect(walk.progressText == "1 of 3")
    #expect(walk.isWalking(key: "trip:t:d"))
    #expect(!walk.isWalking(key: "trip:t:other"))
  }

  @Test func arrivingPausesAndPreviewsTheNextStop() async {
    let walk = walk()
    await walk.start(porto, from: origin)
    await walk.ingest(at(41.1480, -8.6100))
    #expect(walk.phase == .arrived)
    #expect(walk.visited == [0])
    #expect(walk.upcoming == 1)
    #expect(!walk.navigator.isNavigating)
    #expect(walk.navigator.destination?.name == "B")  // preview, not following
    #expect(walk.navigator.leg != nil)

    await walk.walkToNext()
    #expect(walk.phase == .walking)
    #expect(walk.index == 1)
    #expect(walk.navigator.isNavigating)
  }

  @Test func skipJumpsOverTheNextStopAndSkippingTheLastEndsTheDay() async {
    let walk = walk()
    await walk.start(porto, from: origin)
    await walk.ingest(at(41.1480, -8.6100))
    await walk.skip()
    #expect(walk.skipped == [1])
    #expect(walk.phase == .arrived)
    #expect(walk.upcoming == 2)
    #expect(walk.navigator.destination?.name == "C")
    await walk.skip()
    #expect(walk.phase == .done)
    #expect(walk.navigator.remaining.isEmpty)
    #expect(walk.summary.visited == 1)
    #expect(walk.summary.skipped == 2)
  }

  @Test func jumpWalksToAnyStopAndUnskipsIt() async {
    let walk = walk()
    await walk.start(porto, from: origin)
    await walk.ingest(at(41.1480, -8.6100))
    await walk.skip()
    await walk.jump(to: 1)
    #expect(walk.phase == .walking)
    #expect(walk.index == 1)
    #expect(walk.skipped.isEmpty)
    #expect(walk.navigator.destination?.name == "B")
  }

  @Test func arrivingAtTheLastStopFinishesTheDay() async {
    let walk = walk()
    await walk.start(porto, from: origin)
    await walk.jump(to: 2)
    await walk.ingest(at(41.1516, -8.6100))
    #expect(walk.phase == .done)
    #expect(walk.upcoming == nil)
  }

  // Review Focus 1
  @Test func startingOnTopOfStopOneArrivesOnTheFirstFix() async {
    let walk = walk()
    let onA = CLLocationCoordinate2D(latitude: 41.1480, longitude: -8.6100)
    await walk.start(porto, from: onA)
    await walk.ingest(at(41.1480, -8.6100))
    #expect(walk.phase == .arrived)
    #expect(walk.upcoming == 1)
  }

  // Review Focus 2
  @Test func aOneStopDayGoesStraightToDone() async {
    let walk = walk()
    let one = WalkDay(id: "x", title: "Day 1", stops: [porto.stops[0]], withoutLocation: 0)
    await walk.start(one, from: origin)
    await walk.ingest(at(41.1480, -8.6100))
    #expect(walk.phase == .done)
  }

  // Review Focus 4
  @Test func twoStopsInTheSameSpotArriveOneAfterTheOther() async {
    let walk = walk()
    let twin = WalkDay(id: "y", title: "Day 1", stops: [stop("Market", 41.1480, -8.6100), stop("Café", 41.1480, -8.6100)], withoutLocation: 0)
    await walk.start(twin, from: origin)
    await walk.ingest(at(41.1480, -8.6100))
    #expect(walk.phase == .arrived)
    await walk.walkToNext()
    await walk.ingest(at(41.1480, -8.6100))
    #expect(walk.phase == .done)
    #expect(walk.visited == [0, 1])
  }

  @Test func endResetsEverything() async {
    let walk = walk()
    await walk.start(porto, from: origin)
    await walk.end()
    #expect(walk.phase == .idle)
    #expect(walk.day == nil)
    #expect(!walk.navigator.isNavigating)
    #expect(!walk.isWalking(key: "trip:t:d"))
  }

  @Test func nextIndexSkipsSkippedStops() {
    #expect(StopWalk.nextIndex(after: 0, count: 4, skipped: [1, 2]) == 3)
    #expect(StopWalk.nextIndex(after: 2, count: 3, skipped: []) == nil)
    #expect(StopWalk.nextIndex(after: -1, count: 2, skipped: [0]) == 1)
  }
}

struct WalkMapLayerTests {
  @Test func movingMeansGPSSpeedOrARecentStep() {
    let now = Date(timeIntervalSince1970: 100)
    #expect(WalkMapLayer.isMoving(speed: 0.5, lastStepAt: .distantPast, now: now))
    #expect(WalkMapLayer.isMoving(speed: nil, lastStepAt: now.addingTimeInterval(-2), now: now))
    #expect(!WalkMapLayer.isMoving(speed: 0.1, lastStepAt: now.addingTimeInterval(-4), now: now))
    #expect(!WalkMapLayer.isMoving(speed: -1, lastStepAt: .distantPast, now: now))
  }
}
