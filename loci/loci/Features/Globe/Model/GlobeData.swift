import Foundation
import LociConnectProto
import SwiftProtobuf

/// A city the traveller has actually been to (web: `VisitedCity` in
/// lib/api/travel-history.ts). Every one is a real row in the server's
/// user_visited_cities; nothing is inferred from a plan.
nonisolated struct GlobeCity: Identifiable, Equatable, Hashable, Sendable {
  var id: String
  var cityName: String
  /// Empty when the city did not resolve against the cities table. Never
  /// guessed from coordinates.
  var country: String
  var point: GeoPoint
  var visitCount: Int
  var firstVisitAt: Date?
  var lastVisitAt: Date?

  /// Dot radius in points: 4 at one visit up to 9 at ten or more, linear
  /// (web: globeLayers `circle-radius` interpolate 1→4, 10→9).
  var nodeRadius: Double { GlobeFormat.nodeRadius(visitCount: visitCount) }
}

/// One leg between two placed points (web: `GlobeArc`).
nonisolated struct GlobeLeg: Identifiable, Equatable, Hashable, Sendable {
  /// Stable across reloads: see `GlobeLegKey`. Web keys legs by array index,
  /// so a new leg arriving moves the selection to a different one.
  var id: String
  var fromName: String
  var toName: String
  var from: GeoPoint
  var to: GeoPoint
  var distanceKm: Double
  /// Empty when the trip is not linked.
  var tripId: String
  /// "fly", "drive", "rail"… Empty when the trip recorded none; never guessed.
  var mode: String
  /// The day the leg happened, when the trip day has a date.
  var occurredAt: Date?
  /// Not on the wire yet (GlobeArc has no duration); kept so the label is web's.
  var durationMins: Double?

  var label: String { GlobeFormat.legLabel(mode: mode, distanceKm: distanceKm, durationMins: durationMins) }
}

/// Counts for the stats card and the same counts at the start of the period
/// (web: `TravelSummary`). The server's "prev" figures are cumulative totals
/// as they stood `periodDays` ago, so a delta is what this period added.
nonisolated struct TravelSummary: Equatable, Sendable {
  var citiesVisited = 0
  var countriesVisited = 0
  var poisVisited = 0
  var distanceKm = 0.0
  var tripsCompleted = 0
  var citiesVisitedPrev = 0
  var countriesVisitedPrev = 0
  var poisVisitedPrev = 0
  var periodDays = 365
  /// Counts inside the last `periodDays` (proto v5.29.0). Zero from older
  /// servers, which sent all-time totals as they stood when the window opened
  /// in the `*Prev` fields instead of the previous window's counts.
  var citiesVisitedThis = 0
  var countriesVisitedThis = 0
  var poisVisitedThis = 0

  /// True when the server sends window counts. Any non-zero one decides it:
  /// an older server always sends zeros here.
  var hasWindowCounts: Bool { citiesVisitedThis != 0 || countriesVisitedThis != 0 || poisVisitedThis != 0 }

  var citiesTrend: Double? { trend(this: citiesVisitedThis, total: citiesVisited, previous: citiesVisitedPrev) }
  var countriesTrend: Double? { trend(this: countriesVisitedThis, total: countriesVisited, previous: countriesVisitedPrev) }
  var poisTrend: Double? { trend(this: poisVisitedThis, total: poisVisited, previous: poisVisitedPrev) }

  /// This window against the last one; before v5.29.0, the all-time total
  /// against the total when the window opened.
  private func trend(this: Int, total: Int, previous: Int) -> Double? {
    GlobeFormat.trendPercent(current: hasWindowCounts ? this : total, previous: previous)
  }
}

/// Everything the globe renders, from one GetGlobeData call.
nonisolated struct GlobeData: Equatable, Sendable {
  var cities: [GlobeCity]
  var legs: [GlobeLeg]
  var summary: TravelSummary
  /// True once the server has derived history from earlier signals: an empty
  /// globe then means "nowhere yet", not "not worked out yet".
  var backfilled: Bool

  var isEmpty: Bool { cities.isEmpty && legs.isEmpty }

  static let empty = GlobeData(cities: [], legs: [], summary: TravelSummary(), backfilled: false)
}

// MARK: - Mapping

/// Proto → model. proto3 leaves zero values off the wire and Swift's generated
/// defaults are already 0 / "", so a missing field reads as nothing, as web's
/// explicit `?? 0` / `?? ""` do.
nonisolated enum GlobeMapping {
  static func data(_ response: Loci_Travelhistory_GetGlobeDataResponse) -> GlobeData {
    GlobeData(
      cities: response.cities.map(city),
      legs: legs(response.arcs),
      summary: response.hasSummary ? summary(response.summary) : TravelSummary(),
      backfilled: response.backfilled
    )
  }

  static func city(_ c: Loci_Travelhistory_VisitedCity) -> GlobeCity {
    GlobeCity(
      id: c.id.isEmpty ? "\(c.cityName)|\(c.latitude)|\(c.longitude)" : c.id,
      cityName: c.cityName,
      country: c.country,
      point: GeoPoint(latitude: c.latitude, longitude: c.longitude),
      visitCount: Int(c.visitCount),
      firstVisitAt: c.hasFirstVisitAt ? c.firstVisitAt.date : nil,
      lastVisitAt: c.hasLastVisitAt ? c.lastVisitAt.date : nil
    )
  }

  static func legs(_ arcs: [Loci_Travelhistory_GlobeArc]) -> [GlobeLeg] {
    var keys = GlobeLegKey()
    return arcs.map { arc in
      let occurredAt = arc.hasOccurredAt ? arc.occurredAt.date : nil
      return GlobeLeg(
        id: keys.next(tripId: arc.tripID, from: arc.fromName, to: arc.toName, occurredAt: occurredAt),
        fromName: arc.fromName,
        toName: arc.toName,
        from: GeoPoint(latitude: arc.fromLat, longitude: arc.fromLon),
        to: GeoPoint(latitude: arc.toLat, longitude: arc.toLon),
        distanceKm: arc.distanceKm,
        tripId: arc.tripID,
        mode: arc.mode,
        occurredAt: occurredAt,
        durationMins: nil
      )
    }
  }

  static func summary(_ s: Loci_Travelhistory_TravelSummary) -> TravelSummary {
    TravelSummary(
      citiesVisited: Int(s.citiesVisited),
      countriesVisited: Int(s.countriesVisited),
      poisVisited: Int(s.poisVisited),
      distanceKm: s.distanceKm,
      tripsCompleted: Int(s.tripsCompleted),
      citiesVisitedPrev: Int(s.citiesVisitedPrevPeriod),
      countriesVisitedPrev: Int(s.countriesVisitedPrevPeriod),
      poisVisitedPrev: Int(s.poisVisitedPrevPeriod),
      periodDays: s.periodDays > 0 ? Int(s.periodDays) : 365,
      citiesVisitedThis: Int(s.citiesVisitedThisPeriod),
      countriesVisitedThis: Int(s.countriesVisitedThisPeriod),
      poisVisitedThis: Int(s.poisVisitedThisPeriod)
    )
  }
}

/// A leg's identity: trip + from + to + when, so it does not change when
/// legs are added, removed or reordered. The same leg twice in one response
/// (a trip that goes A → B on the same day twice) gets `#2`, `#3` in the
/// order the server sent them.
nonisolated struct GlobeLegKey {
  private var seen: [String: Int] = [:]

  static func base(tripId: String, from: String, to: String, occurredAt: Date?) -> String {
    let when = occurredAt.map { String(Int64(($0.timeIntervalSince1970).rounded())) } ?? "-"
    return [tripId.isEmpty ? "-" : tripId, from, to, when].joined(separator: "|")
  }

  mutating func next(tripId: String, from: String, to: String, occurredAt: Date?) -> String {
    let base = Self.base(tripId: tripId, from: from, to: to, occurredAt: occurredAt)
    let count = (seen[base] ?? 0) + 1
    seen[base] = count
    return count == 1 ? base : "\(base)#\(count)"
  }
}

// MARK: - Formatting

nonisolated enum GlobeFormat {
  /// web: `trendPercent`. The real period-over-period change, or nil when
  /// there is no earlier figure to compare with: an arrow with no baseline is
  /// decoration, so none is drawn.
  static func trendPercent(current: Int, previous: Int) -> Double? {
    guard previous > 0 else { return nil }
    return Double(current - previous) / Double(previous) * 100
  }

  /// "+12%" / "−8%" / "0%", rounded as web rounds (`Math.round`, halves up).
  static func trendText(_ percent: Double) -> String {
    let rounded = Int((percent + 0.5).rounded(.down))
    if rounded == 0 { return "0%" }
    return rounded > 0 ? "+\(rounded)%" : "−\(-rounded)%"
  }

  /// Grouped whole number in `locale` ("1,234" in English, "1.234" in Portuguese).
  static func number(_ value: Double, locale: Locale = .current) -> String {
    let rounded = (value + 0.5).rounded(.down)
    return Int(rounded).formatted(.number.grouping(.automatic).locale(locale))
  }

  static func distance(_ km: Double, locale: Locale = .current) -> String { "\(number(km, locale: locale)) km" }

  /// web: `formatLegLabel`, "fly · 1,234 km · 2h 5m". Each part only when known.
  static func legLabel(mode: String, distanceKm: Double, durationMins: Double?, locale: Locale = .current) -> String {
    var parts: [String] = []
    if !mode.isEmpty { parts.append(mode) }
    if distanceKm > 0 { parts.append(distance(distanceKm, locale: locale)) }
    if let durationMins, durationMins > 0 {
      let hours = Int(durationMins / 60)
      let minutes = Int((durationMins.truncatingRemainder(dividingBy: 60) + 0.5).rounded(.down))
      parts.append(hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m")
    }
    return parts.joined(separator: " · ")
  }

  /// Dot radius, 4 pt at one visit to 9 pt at ten, clamped at both ends.
  static func nodeRadius(visitCount: Int) -> Double {
    let visits = Double(min(max(visitCount, 1), 10))
    return 4 + (visits - 1) * 5 / 9
  }
}
