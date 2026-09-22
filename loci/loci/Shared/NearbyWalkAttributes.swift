import ActivityKit
import Foundation

/// The Live Activity for a Near me walk: what the Lock Screen and the Dynamic
/// Island show while the person is out looking around. Compiled into both the
/// app (which starts and updates it) and the widget extension (which draws it).
public nonisolated struct NearbyWalkAttributes: ActivityAttributes {
  public nonisolated struct ContentState: Codable, Hashable, Sendable {
    public var steps: Int
    public var distanceMeters: Double
    public var placesNearby: Int
    /// The closest place right now, if one is within the walk's reach.
    public var nearestName: String?
    public var nearestMeters: Double?

    public init(steps: Int, distanceMeters: Double, placesNearby: Int, nearestName: String? = nil, nearestMeters: Double? = nil) {
      self.steps = steps
      self.distanceMeters = distanceMeters
      self.placesNearby = placesNearby
      self.nearestName = nearestName
      self.nearestMeters = nearestMeters
    }
  }

  public var startedAt: Date
  public var radiusKm: Int

  public init(startedAt: Date, radiusKm: Int) {
    self.startedAt = startedAt
    self.radiusKm = radiusKm
  }
}

public nonisolated extension NearbyWalkAttributes.ContentState {
  /// "1,840 steps", "1.2 km", "40 m": one formatter for app and widget.
  var stepsText: String { steps.formatted(.number) + (steps == 1 ? " step" : " steps") }

  var distanceText: String { Self.format(meters: distanceMeters) }

  var nearestText: String? {
    guard let nearestName else { return nil }
    if let nearestMeters { return "\(nearestName) · \(Self.format(meters: nearestMeters))" }
    return nearestName
  }

  static func format(meters: Double) -> String {
    meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
  }
}
