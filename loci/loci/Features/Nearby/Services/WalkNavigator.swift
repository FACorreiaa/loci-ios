import CoreLocation
import Foundation
import LociConnectProto
import MapKit
import Observation

/// Walking directions to one place on the Near me map. Tapping a pin previews
/// the route; Go follows it: every location fix trims the line to what is left,
/// strays of more than 40 m fetch a new route, and 25 m from the end is arrival.
/// Owned by `NearbyWalk`, which feeds it the walk's location updates.
@MainActor @Observable final class WalkNavigator {
  /// One walking route: the line, its length, and Apple's time for it.
  nonisolated struct Leg: Equatable, Sendable {
    var coordinates: [CLLocationCoordinate2D]
    var meters: Double
    var expectedTravelTime: TimeInterval

    static func == (a: Leg, b: Leg) -> Bool {
      a.meters == b.meters && a.expectedTravelTime == b.expectedTravelTime
        && a.coordinates.elementsEqual(b.coordinates) { $0.latitude == $1.latitude && $0.longitude == $1.longitude }
    }
  }

  typealias Directions = (CLLocationCoordinate2D, CLLocationCoordinate2D) async throws -> Leg

  /// Strays shorter than this many fixes are GPS noise, not a wrong turn.
  static let offRouteFixes = 2
  /// MKDirections throttles apps that ask too often.
  static let rerouteInterval: TimeInterval = 10

  private(set) var destination: Loci_Poi_POIDetailedInfo?
  private(set) var isNavigating = false
  private(set) var isLoading = false
  /// No walking route came back, so the line is straight.
  private(set) var isStraightLine = false
  private(set) var leg: Leg?
  /// The line still to walk: all of it in preview, trimmed while navigating.
  private(set) var remaining: [CLLocationCoordinate2D] = []
  private(set) var remainingMeters: Double = 0
  private(set) var eta: TimeInterval = 0
  /// Set on arrival, until the card is dismissed.
  private(set) var arrivedAt: String?
  private(set) var rerouteCount = 0

  private let directions: Directions
  private let now: () -> Date
  private var offRouteStreak = 0
  private var lastReroute = Date.distantPast
  private var request = 0

  init(directions: @escaping Directions = WalkNavigator.appleMaps, now: @escaping () -> Date = Date.init) {
    self.directions = directions
    self.now = now
  }

  var destinationCoordinate: CLLocationCoordinate2D? {
    destination.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
  }

  /// Show the route to `poi` without starting anything. Replaces any route
  /// being followed.
  func preview(to poi: Loci_Poi_POIDetailedInfo, from here: CLLocationCoordinate2D) async {
    destination = poi
    isNavigating = false
    arrivedAt = nil
    leg = nil
    remaining = []
    await fetch(from: here)
  }

  /// Follow the previewed route.
  func start() {
    guard destination != nil else { return }
    isNavigating = true
    arrivedAt = nil
    offRouteStreak = 0
  }

  /// Stop following and forget the destination.
  func end() {
    request += 1
    destination = nil
    isNavigating = false
    isLoading = false
    isStraightLine = false
    leg = nil
    remaining = []
    remainingMeters = 0
    eta = 0
    arrivedAt = nil
    offRouteStreak = 0
  }

  /// A location fix from the walk.
  func ingest(_ location: CLLocation) {
    guard isNavigating, let leg else { return }
    let here = location.coordinate
    let left = WalkingRoute.remaining(from: here, along: leg.coordinates)
    remaining = left.coords
    remainingMeters = left.meters
    eta = WalkingRoute.eta(remainingMeters: left.meters, totalMeters: leg.meters, expectedTravelTime: leg.expectedTravelTime)

    if let destinationCoordinate, WalkingRoute.isArrived(meters: WalkingRoute.distance(here, destinationCoordinate)) {
      let name = destination?.name
      end()
      arrivedAt = name ?? "your stop"
      return
    }

    let off = WalkingRoute.project(here, onto: leg.coordinates)?.offRouteMeters ?? 0
    offRouteStreak = WalkingRoute.isOffRoute(meters: off) ? offRouteStreak + 1 : 0
    if offRouteStreak >= Self.offRouteFixes, now().timeIntervalSince(lastReroute) >= Self.rerouteInterval, !isLoading {
      lastReroute = now()
      offRouteStreak = 0
      rerouteCount += 1
      Task { await fetch(from: here) }
    }
  }

  func dismissArrival() { arrivedAt = nil }

  private func fetch(from here: CLLocationCoordinate2D) async {
    guard let to = destinationCoordinate else { return }
    request += 1
    let mine = request
    isLoading = true
    let result: Leg
    var straight = false
    do {
      result = try await directions(here, to)
    } catch {
      let meters = WalkingRoute.distance(here, to)
      result = Leg(coordinates: [here, to], meters: meters, expectedTravelTime: meters / WalkingRoute.walkingSpeed)
      straight = true
    }
    // A newer preview, reroute or end won while this one was in flight.
    guard mine == request else { return }
    isLoading = false
    isStraightLine = straight
    leg = result
    let left = WalkingRoute.remaining(from: here, along: result.coordinates)
    remaining = result.coordinates.count > 1 ? left.coords : result.coordinates
    remainingMeters = left.meters
    eta = WalkingRoute.eta(remainingMeters: left.meters, totalMeters: result.meters, expectedTravelTime: result.expectedTravelTime)
  }

  /// Apple's walking directions. Free, no key, and the same routes Maps shows.
  static let appleMaps: Directions = { from, to in
    let request = MKDirections.Request()
    request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
    request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
    request.transportType = .walking
    let response = try await MKDirections(request: request).calculate()
    guard let route = response.routes.first else { throw MKError(.directionsNotFound) }
    return Leg(coordinates: route.polyline.coordinates, meters: route.distance, expectedTravelTime: route.expectedTravelTime)
  }
}
