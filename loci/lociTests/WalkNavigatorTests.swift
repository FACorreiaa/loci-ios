import CoreLocation
import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Porto, walking east along Rua de Santa Catarina then north: an L of two
/// ~200 m legs, far from the poles so the flat-earth projection holds.
private let start = CLLocationCoordinate2D(latitude: 41.1480, longitude: -8.6100)
private let corner = CLLocationCoordinate2D(latitude: 41.1480, longitude: -8.6076)
private let end = CLLocationCoordinate2D(latitude: 41.1498, longitude: -8.6076)
private let route = [start, corner, end]

private func at(_ c: CLLocationCoordinate2D, dLat: Double = 0, dLon: Double = 0, course: Double = -1, speed: Double = 0) -> CLLocation {
  CLLocation(
    coordinate: CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLon),
    altitude: 0,
    horizontalAccuracy: 5,
    verticalAccuracy: 5,
    course: course,
    speed: speed,
    timestamp: Date()
  )
}

struct WalkingRouteTests {
  @Test func snapsOntoTheNearestSegment() throws {
    // ~22 m north of the first leg's midpoint.
    let beside = CLLocationCoordinate2D(latitude: 41.1482, longitude: -8.6088)
    let p = try #require(WalkingRoute.project(beside, onto: route))
    #expect(p.index == 0)
    #expect(abs(p.snapped.latitude - 41.1480) < 1e-6)
    #expect(p.offRouteMeters > 18 && p.offRouteMeters < 26)
    #expect(!WalkingRoute.isOffRoute(meters: p.offRouteMeters))
    #expect(WalkingRoute.isOffRoute(meters: 41))
  }

  @Test func remainingShrinksAlongTheL() {
    let total = WalkingRoute.length(of: route)
    let fromStart = WalkingRoute.remaining(from: start, along: route)
    let fromCorner = WalkingRoute.remaining(from: corner, along: route)
    let nearEnd = WalkingRoute.remaining(from: CLLocationCoordinate2D(latitude: 41.1496, longitude: -8.6076), along: route)
    #expect(abs(fromStart.meters - total) < 1)
    #expect(fromCorner.meters < fromStart.meters)
    #expect(fromCorner.coords.count == 2)
    #expect(nearEnd.meters < 30)
    #expect(WalkingRoute.isArrived(meters: nearEnd.meters))
    #expect(!WalkingRoute.isArrived(meters: 26))
  }

  @Test func etaScalesTheRouteTimeOrFallsBackToWalkingPace() {
    #expect(WalkingRoute.eta(remainingMeters: 500, totalMeters: 1000, expectedTravelTime: 800) == 400)
    #expect(abs(WalkingRoute.eta(remainingMeters: 135, totalMeters: 0, expectedTravelTime: 0) - 100) < 0.001)
    #expect(NearbyWalkAttributes.ContentState.format(eta: 20) == "1 min")
    #expect(NearbyWalkAttributes.ContentState.format(eta: 4000) == "1 h 7 min")
  }

  @Test func headingUsesCourseOnlyWhenReallyMoving() throws {
    // Standing still: GPS course is -1, so face the next point (east ≈ 90°).
    let still = try #require(WalkingRoute.heading(course: -1, speed: 0, from: start, toward: corner))
    #expect(abs(still - 90) < 1)
    #expect(WalkingRoute.heading(course: 200, speed: 1.4, from: start, toward: corner) == 200)
    #expect(WalkingRoute.heading(course: 200, speed: 0.2, from: start, toward: nil) == nil)
  }

  @Test func walkerFacesLeftOnlyWhenHeadingWest() {
    #expect(!WalkingRoute.facesLeft(heading: 0))
    #expect(!WalkingRoute.facesLeft(heading: 90))
    #expect(!WalkingRoute.facesLeft(heading: 180))
    #expect(WalkingRoute.facesLeft(heading: 270))
    #expect(WalkingRoute.facesLeft(heading: -45))
    #expect(!WalkingRoute.facesLeft(heading: 450))
  }
}

@MainActor struct WalkNavigatorTests {
  private var destination: Loci_Poi_POIDetailedInfo {
    var poi = Loci_Poi_POIDetailedInfo()
    poi.id = "bolhao"
    poi.name = "Bolhão"
    poi.latitude = end.latitude
    poi.longitude = end.longitude
    return poi
  }

  private let leg = WalkNavigator.Leg(coordinates: route, meters: WalkingRoute.length(of: route), expectedTravelTime: 300)

  @Test func previewDrawsTheWholeRouteThenIngestTrimsIt() async {
    let navigator = WalkNavigator(directions: { [leg] _, _ in leg })
    await navigator.preview(to: destination, from: start)
    #expect(navigator.remaining.count == 3)
    #expect(!navigator.isNavigating)

    // Not following yet: fixes change nothing.
    navigator.ingest(at(corner))
    #expect(navigator.remaining.count == 3)

    navigator.start()
    navigator.ingest(at(corner))
    #expect(navigator.remaining.count == 2)
    #expect(navigator.remainingMeters < leg.meters)
    #expect(navigator.eta < 300)
  }

  @Test func twoStraysRerouteOnceWithinTheThrottle() async throws {
    var clock = Date(timeIntervalSince1970: 0)
    var calls = 0
    let navigator = WalkNavigator(directions: { [leg] _, _ in calls += 1; return leg }, now: { clock })
    await navigator.preview(to: destination, from: start)
    navigator.start()
    #expect(calls == 1)

    let stray = at(start, dLat: -0.001)  // ~110 m south of the line
    navigator.ingest(stray)
    #expect(navigator.rerouteCount == 0)  // one stray fix is noise
    navigator.ingest(stray)
    #expect(navigator.rerouteCount == 1)
    try await Task.sleep(for: .milliseconds(50))
    #expect(calls == 2)

    clock += 5
    navigator.ingest(stray)
    navigator.ingest(stray)
    #expect(navigator.rerouteCount == 1)  // throttled

    clock += 10
    navigator.ingest(stray)
    navigator.ingest(stray)
    #expect(navigator.rerouteCount == 2)
  }

  @Test func arrivalEndsTheRouteAndSaysWhere() async {
    let navigator = WalkNavigator(directions: { [leg] _, _ in leg })
    await navigator.preview(to: destination, from: start)
    navigator.start()
    navigator.ingest(at(end, dLat: -0.0001))  // ~11 m short
    #expect(navigator.arrivedAt == "Bolhão")
    #expect(!navigator.isNavigating)
    #expect(navigator.destination == nil)
    #expect(navigator.remaining.isEmpty)
    navigator.dismissArrival()
    #expect(navigator.arrivedAt == nil)
  }

  @Test func noRouteFallsBackToAStraightLine() async {
    let navigator = WalkNavigator(directions: { _, _ in throw URLError(.notConnectedToInternet) })
    await navigator.preview(to: destination, from: start)
    #expect(navigator.isStraightLine)
    #expect(navigator.remaining.count == 2)
    #expect(navigator.leg != nil)  // Go still works
    #expect(abs(navigator.remainingMeters - WalkingRoute.distance(start, end)) < 1)
  }

  @Test func aNewerPreviewWinsOverASlowOne() async {
    var slow = true
    let navigator = WalkNavigator(directions: { [leg] _, _ in
      if slow {
        slow = false
        try await Task.sleep(for: .milliseconds(100))
      }
      return leg
    })
    var other = destination
    other.id = "other"
    other.name = "Other"
    async let first: Void = navigator.preview(to: destination, from: start)
    try? await Task.sleep(for: .milliseconds(10))
    await navigator.preview(to: other, from: start)
    await first
    #expect(navigator.destination?.name == "Other")
    #expect(!navigator.isLoading)
  }
}

struct NearbyWalkDestinationTests {
  @Test func destinationTextAndOldPayloadsStillDecode() throws {
    let state = NearbyWalkAttributes.ContentState(
      steps: 10, distanceMeters: 5, placesNearby: 1, destinationName: "Bolhão", destinationMeters: 400, etaSeconds: 290
    )
    #expect(state.destinationText == "Bolhão · 400 m · 5 min")

    // An activity started by a build without the destination fields.
    let old = #"{"steps":12,"distanceMeters":8.5,"placesNearby":3,"nearestName":"Gaia"}"#
    let decoded = try JSONDecoder().decode(NearbyWalkAttributes.ContentState.self, from: Data(old.utf8))
    #expect(decoded.steps == 12)
    #expect(decoded.destinationName == nil)
    #expect(decoded.destinationText == nil)
  }
}
