import CoreLocation
import MapKit

/// Fans out numbered pins that would draw on top of each other at the current
/// zoom (a pack's "1 under 2" when two stops sit a street apart).
///
/// Pins are projected to screen points at `mapPointsPerPoint`; any that come
/// closer than a pin's diameter join a cluster (transitively), and each
/// cluster's members are placed on a small ring around its centre in number
/// order, starting on the left and going clockwise. The result moves the
/// annotation's coordinate, not its view, so taps still land on the pin.
nonisolated enum PinSpread {
  struct Input {
    let id: String
    let coordinate: CLLocationCoordinate2D
  }

  /// A 26-point `MapPin` plus a hairline gap.
  static let pinDiameter: Double = 28

  /// The coordinate each crowded pin should be drawn at, keyed by pin id.
  /// Pins with room of their own are left out.
  static func coordinates(for pins: [Input], mapPointsPerPoint: Double, diameter: Double = pinDiameter) -> [String: CLLocationCoordinate2D] {
    guard pins.count > 1, mapPointsPerPoint > 0 else { return [:] }
    let points = pins.map { MKMapPoint($0.coordinate) }
    let screen = points.map { CGPoint(x: $0.x / mapPointsPerPoint, y: $0.y / mapPointsPerPoint) }

    // Union-find over every pair that would overlap.
    var parent = Array(pins.indices)
    func root(_ index: Int) -> Int {
      var index = index
      while parent[index] != index {
        parent[index] = parent[parent[index]]
        index = parent[index]
      }
      return index
    }
    for lhs in pins.indices {
      for rhs in pins.indices where rhs > lhs {
        let distance = hypot(screen[lhs].x - screen[rhs].x, screen[lhs].y - screen[rhs].y)
        if distance < diameter { parent[root(rhs)] = root(lhs) }
      }
    }

    var clusters: [Int: [Int]] = [:]
    for index in pins.indices { clusters[root(index), default: []].append(index) }

    var result: [String: CLLocationCoordinate2D] = [:]
    for members in clusters.values where members.count > 1 {
      let count = Double(members.count)
      let centre = CGPoint(
        x: members.map { screen[$0].x }.reduce(0, +) / count,
        y: members.map { screen[$0].y }.reduce(0, +) / count
      )
      // Neighbours on the ring sit one diameter apart.
      let radius = diameter / (2 * sin(.pi / count))
      for (slot, member) in members.sorted().enumerated() {
        let angle = Double.pi + 2 * .pi * Double(slot) / count
        let target = MKMapPoint(
          x: (centre.x + radius * cos(angle)) * mapPointsPerPoint,
          y: (centre.y + radius * sin(angle)) * mapPointsPerPoint
        )
        result[pins[member].id] = target.coordinate
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
