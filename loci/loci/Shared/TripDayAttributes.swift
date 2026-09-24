import ActivityKit
import Foundation

/// The Live Activity for a trip day: the stop you are at, how long the plan
/// gives it, and what comes next. Compiled into the app (which starts and
/// updates it) and the widget extension (which draws it).
public nonisolated struct TripDayAttributes: ActivityAttributes {
  public nonisolated enum Phase: String, Codable, Hashable, Sendable {
    case beforeFirst = "before_first"
    case atStop = "at_stop"
    case between
    case done
  }

  public nonisolated struct ContentState: Codable, Hashable, Sendable {
    public var phase: Phase
    public var currentIndex: Int
    public var currentName: String
    /// The end of the current slot; the widget counts down to it.
    public var slotEnd: Date
    public var nextName: String?
    public var nextDistanceMeters: Double?
    public var stopsDone: Int

    public init(
      phase: Phase,
      currentIndex: Int,
      currentName: String,
      slotEnd: Date,
      nextName: String? = nil,
      nextDistanceMeters: Double? = nil,
      stopsDone: Int
    ) {
      self.phase = phase
      self.currentIndex = currentIndex
      self.currentName = currentName
      self.slotEnd = slotEnd
      self.nextName = nextName
      self.nextDistanceMeters = nextDistanceMeters
      self.stopsDone = stopsDone
    }
  }

  public var tripId: String
  public var dayId: String
  public var cityName: String
  public var stopCount: Int
  public var startedAt: Date

  public init(tripId: String, dayId: String, cityName: String, stopCount: Int, startedAt: Date) {
    self.tripId = tripId
    self.dayId = dayId
    self.cityName = cityName
    self.stopCount = stopCount
    self.startedAt = startedAt
  }
}

public nonisolated extension TripDayAttributes.ContentState {
  /// "Next: Pantheon · 1.2 km": one formatter for app and widget.
  var nextText: String? {
    guard let nextName else { return nil }
    guard let meters = nextDistanceMeters else { return "Next: \(nextName)" }
    let distance = meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters.rounded())) m"
    return "Next: \(nextName) · \(distance)"
  }

  func progressText(of stopCount: Int) -> String { "\(stopsDone)/\(stopCount)" }
}
