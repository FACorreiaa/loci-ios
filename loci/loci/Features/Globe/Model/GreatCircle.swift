import Foundation

/// A latitude/longitude pair in degrees. Plain values so the geometry below is
/// testable without MapKit; the view turns them into `CLLocationCoordinate2D`.
nonisolated struct GeoPoint: Equatable, Hashable, Sendable {
  var latitude: Double
  var longitude: Double
}

/// Great-circle arcs, ported from web's `components/features/Map/geo.ts`.
///
/// `path` keeps web's densification: MapKit, like Mapbox, joins polyline
/// vertices with straight lines in projected space, so a two-point Lisbon →
/// Tokyo line would draw as a chord. Where web then unwraps longitudes past
/// ±180 (Mapbox draws those across the seam), MapKit does not, so `segments`
/// cuts the unwrapped path at the antimeridian instead.
nonisolated enum GreatCircle {
  static let earthRadiusKm = 6371.0088
  private static let rad = Double.pi / 180

  /// Central angle between two points, in radians (inputs in radians).
  private static func centralAngle(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let a = pow(sin((lat2 - lat1) / 2), 2) + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)
    return 2 * asin(min(1, a.squareRoot()))
  }

  /// Great-circle distance in km (web: `haversineKm`, which mirrors the server's
  /// `HaversineKm`, so a leg's label and its curve agree).
  static func distanceKm(_ from: GeoPoint, _ to: GeoPoint) -> Double {
    earthRadiusKm * centralAngle(from.latitude * rad, from.longitude * rad, to.latitude * rad, to.longitude * rad)
  }

  /// Vertices for an arc of `degrees`: one per 2°, clamped to 24…128 (web).
  static func segmentCount(degrees: Double) -> Int { min(128, max(24, Int((degrees / 2).rounded(.up)))) }

  /// The densified great circle from `from` to `to`, `segmentCount + 1`
  /// points, with longitudes unwrapped so consecutive points never jump more
  /// than 180° (they can leave −180…180; `segments` puts them back).
  /// Coincident endpoints have no unique great circle and come back as-is.
  static func path(from: GeoPoint, to: GeoPoint) -> [GeoPoint] {
    let lon1 = from.longitude * rad
    let lat1 = from.latitude * rad
    let lon2 = to.longitude * rad
    let lat2 = to.latitude * rad

    let d = centralAngle(lat1, lon1, lat2, lon2)
    let sinD = sin(d)
    // Antipodal endpoints are degenerate too (sin d = 0): any meridian would do.
    guard d.isFinite, d >= 1e-9, abs(sinD) > 1e-12 else { return [from, to] }

    let n = segmentCount(degrees: d / rad)
    var out: [GeoPoint] = []
    out.reserveCapacity(n + 1)
    for i in 0...n {
      let f = Double(i) / Double(n)
      let a = sin((1 - f) * d) / sinD
      let b = sin(f * d) / sinD
      let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
      let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
      let z = a * sin(lat1) + b * sin(lat2)
      out.append(GeoPoint(latitude: atan2(z, (x * x + y * y).squareRoot()) / rad, longitude: atan2(y, x) / rad))
    }
    return unwrapAntimeridian(out)
  }

  /// web: `unwrapAntimeridian`. Rewrites longitudes so consecutive points never
  /// jump more than 180°.
  static func unwrapAntimeridian(_ points: [GeoPoint]) -> [GeoPoint] {
    guard var previous = points.first else { return [] }
    var out = [previous]
    out.reserveCapacity(points.count)
    for var point in points.dropFirst() {
      while point.longitude - previous.longitude > 180 { point.longitude -= 360 }
      while point.longitude - previous.longitude < -180 { point.longitude += 360 }
      out.append(point)
      previous = point
    }
    return out
  }

  /// Folds a longitude into −180…180 (180 stays 180, so a seam point keeps its side).
  static func normalizedLongitude(_ longitude: Double) -> Double {
    var lon = longitude.truncatingRemainder(dividingBy: 360)
    if lon > 180 { lon -= 360 }
    if lon < -180 { lon += 360 }
    return lon
  }

  /// An unwrapped path as pieces MapKit can draw, each within −180…180. Where
  /// the path crosses the antimeridian it is cut, with a point on the seam at
  /// the interpolated latitude ending one piece (at ±180) and starting the next
  /// (at ∓180), so the arc leaves no gap and never streaks across the map.
  static func segments(_ unwrapped: [GeoPoint]) -> [[GeoPoint]] {
    guard let first = unwrapped.first else { return [] }
    // Which 360°-wide band a longitude is in: band 0 is −180…180.
    func band(_ lon: Double) -> Int { Int(((lon + 180) / 360).rounded(.down)) }

    var pieces: [[GeoPoint]] = []
    // A point's longitude inside its own band, so one exactly on the seam
    // (180 after an eastward crossing) lands on the side it was drawn from.
    func local(_ point: GeoPoint) -> GeoPoint { GeoPoint(latitude: point.latitude, longitude: point.longitude - Double(band(point.longitude)) * 360) }
    func append(_ point: GeoPoint, to piece: inout [GeoPoint]) { if piece.last != point { piece.append(point) } }

    var current = [local(first)]
    var previous = first
    for point in unwrapped.dropFirst() {
      let from = band(previous.longitude)
      let to = band(point.longitude)
      if from != to {
        // The seam between the bands, in unwrapped degrees.
        let seam = Double(max(from, to)) * 360 - 180
        let span = point.longitude - previous.longitude
        let t = span == 0 ? 0 : (seam - previous.longitude) / span
        let latitude = previous.latitude + (point.latitude - previous.latitude) * t
        let eastward = to > from
        append(GeoPoint(latitude: latitude, longitude: eastward ? 180 : -180), to: &current)
        pieces.append(current)
        current = [GeoPoint(latitude: latitude, longitude: eastward ? -180 : 180)]
      }
      append(local(point), to: &current)
      previous = point
    }
    pieces.append(current)
    // A crossing exactly on a vertex can leave a one-point piece; drop it.
    return pieces.filter { $0.count > 1 }
  }

  /// The point halfway along the arc, for a leg's label and camera.
  static func midpoint(from: GeoPoint, to: GeoPoint) -> GeoPoint {
    let points = path(from: from, to: to)
    let middle = points[points.count / 2]
    return GeoPoint(latitude: middle.latitude, longitude: normalizedLongitude(middle.longitude))
  }

  /// Where to point the globe at first: the mean of the points on the sphere
  /// (so Fiji and Samoa average near the antimeridian, not near Greenwich).
  /// Nil for no points, or points that cancel out.
  static func centroid(_ points: [GeoPoint]) -> GeoPoint? {
    var x = 0.0
    var y = 0.0
    var z = 0.0
    for point in points {
      let lat = point.latitude * rad
      let lon = point.longitude * rad
      x += cos(lat) * cos(lon)
      y += cos(lat) * sin(lon)
      z += sin(lat)
    }
    let horizontal = (x * x + y * y).squareRoot()
    guard horizontal > 1e-9 || abs(z) > 1e-9 else { return nil }
    return GeoPoint(latitude: atan2(z, horizontal) / rad, longitude: atan2(y, x) / rad)
  }
}
