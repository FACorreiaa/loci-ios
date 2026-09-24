import CoreLocation
import Foundation
import MapKit

/// Geometry for walking a route: where on the line you are, how much of it is
/// left, whether you have strayed or arrived, and which way the walker faces.
/// Pure and synchronous so every threshold is unit-tested; `WalkNavigator`
/// owns the state and the directions requests.
nonisolated enum WalkingRoute {
  /// Further than this from the line counts as off route.
  static let offRouteMeters: Double = 40
  /// Closer than this to the end counts as there.
  static let arrivalMeters: Double = 25
  /// A comfortable walking pace, for when there is no route time to scale.
  static let walkingSpeed: Double = 1.35
  /// `figure.walk` is drawn striding to the right.
  static let symbolFacesRight = true

  /// The nearest point on the line to a location, the segment it lies on
  /// (`coords[index]` → `coords[index + 1]`), and how far away it is.
  struct Projection {
    var index: Int
    var snapped: CLLocationCoordinate2D
    var offRouteMeters: Double
  }

  static func project(_ point: CLLocationCoordinate2D, onto coords: [CLLocationCoordinate2D]) -> Projection? {
    guard let first = coords.first else { return nil }
    guard coords.count > 1 else { return Projection(index: 0, snapped: first, offRouteMeters: distance(point, first)) }
    // Metres on a plane tangent at `point`: exact enough over a city walk.
    let metersPerDegree = 111_320.0
    let lonScale = cos(point.latitude * .pi / 180) * metersPerDegree
    func local(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
      ((c.longitude - point.longitude) * lonScale, (c.latitude - point.latitude) * metersPerDegree)
    }
    var best: Projection?
    for index in 0..<(coords.count - 1) {
      let a = local(coords[index]), b = local(coords[index + 1])
      let dx = b.x - a.x, dy = b.y - a.y
      let lengthSquared = dx * dx + dy * dy
      // Point is the origin, so the projection of (0 - a) onto ab.
      let t = lengthSquared == 0 ? 0 : max(0, min(1, (-a.x * dx - a.y * dy) / lengthSquared))
      let x = a.x + t * dx, y = a.y + t * dy
      let meters = (x * x + y * y).squareRoot()
      if meters < best?.offRouteMeters ?? .infinity {
        let snapped = CLLocationCoordinate2D(latitude: point.latitude + y / metersPerDegree, longitude: point.longitude + x / lonScale)
        best = Projection(index: index, snapped: snapped, offRouteMeters: meters)
      }
    }
    return best
  }

  /// The line still to walk, starting where `point` snaps onto it.
  static func remaining(from point: CLLocationCoordinate2D, along coords: [CLLocationCoordinate2D]) -> (coords: [CLLocationCoordinate2D], meters: Double) {
    guard let projection = project(point, onto: coords) else { return ([], 0) }
    var rest = Array(coords.dropFirst(projection.index + 1))
    // Standing on a vertex snaps to the end of the segment before it: don't
    // draw that vertex twice.
    if let next = rest.first, distance(projection.snapped, next) < 0.5 { rest.removeFirst() }
    let line = [projection.snapped] + rest
    return (line, length(of: line))
  }

  static func length(of coords: [CLLocationCoordinate2D]) -> Double {
    zip(coords, coords.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
  }

  /// The route's own time, scaled to what is left of it.
  static func eta(remainingMeters: Double, totalMeters: Double, expectedTravelTime: TimeInterval) -> TimeInterval {
    guard totalMeters > 0, expectedTravelTime > 0 else { return remainingMeters / walkingSpeed }
    return expectedTravelTime * remainingMeters / totalMeters
  }

  static func isOffRoute(meters: Double) -> Bool { meters > offRouteMeters }

  static func isArrived(meters: Double) -> Bool { meters <= arrivalMeters }

  /// The GPS course once you are really moving; before that (course is -1 or
  /// jittery at a standstill) the direction of the next point on the line.
  static func heading(course: CLLocationDirection, speed: CLLocationSpeed, from here: CLLocationCoordinate2D, toward next: CLLocationCoordinate2D?) -> CLLocationDirection? {
    if course >= 0, speed > 0.5 { return course }
    guard let next else { return nil }
    return bearing(from: here, to: next)
  }

  /// The walker is mirrored rather than rotated, so it stays upright: it faces
  /// left for anything heading west of north–south.
  static func facesLeft(heading: CLLocationDirection) -> Bool {
    let h = heading.truncatingRemainder(dividingBy: 360)
    let normalized = h < 0 ? h + 360 : h
    return normalized > 180 && normalized < 360
  }

  static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDirection {
    let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    let degrees = atan2(y, x) * 180 / .pi
    return degrees < 0 ? degrees + 360 : degrees
  }

  static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
  }

  /// A camera rect for the whole line, padded, and twice as tall so the line
  /// sits in the top half while the sheet covers the bottom.
  static func mapRect(for coords: [CLLocationCoordinate2D]) -> MKMapRect? {
    guard coords.count > 1 else { return nil }
    let rect = MKPolyline(coordinates: coords, count: coords.count).boundingMapRect
    let pad = max(rect.width, rect.height, 400) * 0.25
    var padded = rect.insetBy(dx: -pad, dy: -pad)
    padded.size.height *= 2
    return padded
  }
}

extension MKPolyline {
  nonisolated var coordinates: [CLLocationCoordinate2D] {
    var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
    getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
    return coords
  }
}
