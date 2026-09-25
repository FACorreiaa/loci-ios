import CoreLocation
import MapKit

/// Nudges numbered pins apart when they would draw on top of each other at
/// the current zoom (a pack's "1 under 2" when two stops sit a street apart).
///
/// Pins are projected to screen points at `mapPointsPerPoint`, then relaxed:
/// every pair closer than a pin's diameter is pushed apart along the line
/// between them, a few dozen rounds, so crowded pins end up touching rather
/// than stacked and each stays as close to its place as the others allow.
/// Pins on the exact same spot split left to right in number order. The
/// result moves the annotation's coordinate, not its view, so taps still land.
nonisolated enum PinSpread {
  struct Input {
    let id: String
    let coordinate: CLLocationCoordinate2D
  }

  /// A 26-point `MapPin` plus a hairline gap.
  static let pinDiameter: Double = 28

  /// The coordinate each crowded pin should be drawn at, keyed by pin id.
  /// Pins with room of their own are left out.
  static func coordinates(
    for pins: [Input],
    mapPointsPerPoint: Double,
    diameter: Double = pinDiameter,
    rounds: Int = 60
  ) -> [String: CLLocationCoordinate2D] {
    guard pins.count > 1, mapPointsPerPoint > 0 else { return [:] }
    let origin = pins.map { MKMapPoint($0.coordinate) }
    var xs = origin.map { $0.x / mapPointsPerPoint }
    var ys = origin.map { $0.y / mapPointsPerPoint }
    let crowded = { (lhs: Int, rhs: Int) in hypot(xs[lhs] - xs[rhs], ys[lhs] - ys[rhs]) < diameter - 0.01 }
    guard pins.indices.contains(where: { lhs in pins.indices.contains { $0 > lhs && crowded(lhs, $0) } }) else { return [:] }

    for _ in 0..<rounds {
      var moved = false
      for lhs in pins.indices {
        for rhs in pins.indices where rhs > lhs {
          var dx = xs[rhs] - xs[lhs]
          var dy = ys[rhs] - ys[lhs]
          var distance = hypot(dx, dy)
          guard distance < diameter - 0.01 else { continue }
          if distance < 0.01 {
            // Same spot: the lower number goes left.
            (dx, dy, distance) = (1, 0, 1)
          }
          let push = (diameter - hypot(xs[rhs] - xs[lhs], ys[rhs] - ys[lhs])) / 2
          xs[lhs] -= dx / distance * push
          ys[lhs] -= dy / distance * push
          xs[rhs] += dx / distance * push
          ys[rhs] += dy / distance * push
          moved = true
        }
      }
      if !moved { break }
    }

    var result: [String: CLLocationCoordinate2D] = [:]
    for index in pins.indices {
      let point = MKMapPoint(x: xs[index] * mapPointsPerPoint, y: ys[index] * mapPointsPerPoint)
      if hypot(point.x - origin[index].x, point.y - origin[index].y) / mapPointsPerPoint > 0.5 {
        result[pins[index].id] = point.coordinate
      }
    }
    return result
  }

  /// Map points per screen point when `.automatic` fits `pins` into `size`,
  /// with MapKit's edge padding (roughly 15%) folded in.
  static func fittedScale(for pins: [Input], in size: CGSize, padding: Double = 1.15) -> Double? {
    guard pins.count > 1, size.width > 0, size.height > 0 else { return nil }
    let points = pins.map { MKMapPoint($0.coordinate) }
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
    let scale = max((maxX - minX) / size.width, (maxY - minY) / size.height) * padding
    return scale > 0 ? scale : nil
  }
}
