import Foundation
import LociConnectProto

/// One pack in the catalog (web: lib/api/bundles.ts `toPack`).
///
/// There is deliberately no price here. iOS never sells a pack (App Store
/// 3.1.1), so it never shows what one costs; a paid pack the caller does not
/// own is simply locked.
nonisolated struct PackSummary: Equatable, Hashable, Identifiable, Sendable {
  var id: String
  var slug: String
  var title: String
  var summary: String
  var cityName: String
  var theme: String
  var months: [Int]
  var dayCount: Int
  var stopCount: Int
  var isPaid: Bool
  var owned: Bool

  init(
    id: String,
    slug: String,
    title: String,
    summary: String = "",
    cityName: String,
    theme: String,
    months: [Int] = [],
    dayCount: Int,
    stopCount: Int,
    isPaid: Bool = false,
    owned: Bool = false
  ) {
    self.id = id
    self.slug = slug
    self.title = title
    self.summary = summary
    self.cityName = cityName
    self.theme = theme
    self.months = months
    self.dayCount = dayCount
    self.stopCount = stopCount
    self.isPaid = isPaid
    self.owned = owned
  }

  init(_ bundle: Loci_Bundle_V1_Bundle) {
    self.init(
      id: bundle.id,
      slug: bundle.slug,
      title: bundle.title,
      summary: bundle.summary,
      cityName: bundle.cityName,
      theme: bundle.theme,
      months: bundle.months.map(Int.init),
      dayCount: Int(bundle.dayCount),
      stopCount: Int(bundle.stopCount),
      isPaid: bundle.isPaid,
      owned: bundle.owned
    )
  }

  /// web: PackCard's badge. "✓ Yours" is only for a paid pack you own; a free
  /// pack reads Free even though the server reports it as owned.
  var badge: PackBadge {
    if isPaid, !owned { return .locked }
    return isPaid ? .yours : .free
  }

  /// "3 days · 12 stops"
  var sizeLabel: String { "\(dayCount) \(dayCount == 1 ? "day" : "days") · \(stopCount) \(stopCount == 1 ? "stop" : "stops")" }
}

nonisolated enum PackBadge: Equatable, Sendable {
  case free, yours, locked

  var label: String {
    switch self {
    case .free: "Free"
    case .yours: "Yours"
    case .locked: "Locked"
    }
  }

  var systemImage: String? {
    switch self {
    case .free: nil
    case .yours: "checkmark"
    case .locked: "lock.fill"
    }
  }
}

/// A stop with a position (web: lib/bundles/points.ts `PackPoint`).
nonisolated struct PackPoint: Equatable, Sendable {
  let id: String
  let name: String
  let category: String
  let latitude: Double
  let longitude: Double
  /// 0-based, to match the list's day grouping.
  let day: Int
  /// 1-based position across the whole pack.
  let seq: Int
}

nonisolated enum PackPoints {
  /// web: pointsFromDays. Every stop that has a position, in visiting order.
  ///
  /// The server hydrates a stop's stored position into `poi`, because TripStop
  /// carries no coordinates. A stop without one has no `poi` at all (rather
  /// than 0,0, which is a real place in the Atlantic), so absence is the signal
  /// to skip it. `seq` stays contiguous across the skips.
  static func from(_ days: [Loci_Bundle_V1_BundleDay]) -> [PackPoint] {
    var points: [PackPoint] = []
    for day in days {
      for (index, stop) in day.stops.enumerated() {
        guard stop.hasPoi, stop.poi.hasLatitude, stop.poi.hasLongitude else { continue }
        points.append(
          PackPoint(
            id: PackStop.key(stop, dayNumber: Int(day.dayNumber), index: index),
            name: stop.name,
            category: stop.poi.category,
            latitude: stop.poi.latitude,
            longitude: stop.poi.longitude,
            day: Int(day.dayNumber) - 1,
            seq: points.count + 1
          )
        )
      }
    }
    return points
  }
}

/// One authored stop (web: `toDetail`'s ItineraryStop).
nonisolated struct PackStop: Equatable, Sendable {
  /// The stop's id, or "day-index" when it has none.
  let key: String
  let name: String
  /// The author's notes: what the list shows under the name.
  let blurb: String
  /// 0-based: the server numbers days from 1.
  let day: Int
  /// The real POI id, when the pack still links to one.
  let placeId: String?
  /// "90 min"
  let timeToSpend: String?
  /// The hydrated place (position, category, address), when there is one.
  let poi: Loci_Poi_POIDetailedInfo?
  /// The id the shared result components key on (`stableID`). The real POI id
  /// where it is unique in the pack, so a Save or facts lookup from the full
  /// map hits the right place; empty with no POI (the name keys it); the stop's
  /// key for a place visited a second time, so ForEach and pins stay unique.
  var cardID: String

  static func key(_ stop: Loci_Trip_TripStop, dayNumber: Int, index: Int) -> String { stop.id.isEmpty ? "\(dayNumber)-\(index)" : stop.id }

  init(_ stop: Loci_Trip_TripStop, dayNumber: Int, index: Int) {
    key = Self.key(stop, dayNumber: dayNumber, index: index)
    name = stop.name
    blurb = stop.notes
    day = dayNumber - 1
    placeId = stop.poiID.isEmpty ? nil : stop.poiID
    timeToSpend = stop.hasDurationMinutes && stop.durationMinutes > 0 ? "\(stop.durationMinutes) min" : nil
    poi = stop.hasPoi ? stop.poi : nil
    cardID = placeId ?? ""
  }

  /// The place as the shared result components want it (`StopCard`, the map).
  var card: Loci_Poi_POIDetailedInfo {
    var place = poi ?? Loci_Poi_POIDetailedInfo()
    place.id = cardID
    if !name.isEmpty { place.name = name }
    if !blurb.isEmpty { place.descriptionPoi = blurb }
    place.day = Int32(day + 1)
    return place
  }

  /// The place for `PlaceDetailView`, always keyed by the real POI id (or
  /// none), even for a repeat visit whose card is keyed by the stop.
  var detailPlace: Loci_Poi_POIDetailedInfo {
    var place = card
    place.id = placeId ?? ""
    return place
  }
}

nonisolated struct PackDay: Equatable, Sendable {
  /// 1-based, as the server sends it.
  let dayNumber: Int
  let title: String
  let stops: [PackStop]
}

/// How much of the pack the caller may read.
nonisolated enum PackAccess: Equatable, Sendable {
  /// Every day is here: free, or paid and owned. It can be opened as a trip.
  case unlocked
  /// Only the preview days came back; this many more exist.
  case locked(days: Int)
}

/// One pack with the days the caller may read (web: `toDetail`).
nonisolated struct PackDetail: Equatable, Sendable {
  let pack: PackSummary
  let days: [PackDay]
  /// Every stop that has a position, in visiting order.
  let points: [PackPoint]
  let lockedDayCount: Int

  init(pack: PackSummary, days: [PackDay], points: [PackPoint], lockedDayCount: Int) {
    self.pack = pack
    self.days = days
    self.points = points
    self.lockedDayCount = lockedDayCount
  }

  init(_ detail: Loci_Bundle_V1_BundleDetail) {
    pack = PackSummary(detail.bundle)
    lockedDayCount = Int(detail.lockedDayCount)
    points = PackPoints.from(detail.days)
    var seen = Set<String>()
    days = detail.days.map { day in
      let stops = day.stops.enumerated().map { index, proto in
        var stop = PackStop(proto, dayNumber: Int(day.dayNumber), index: index)
        if let placeId = stop.placeId, !seen.insert(placeId).inserted { stop.cardID = stop.key }
        return stop
      }
      return PackDay(dayNumber: Int(day.dayNumber), title: day.title, stops: stops)
    }
  }

  var access: PackAccess { lockedDayCount > 0 ? .locked(days: lockedDayCount) : .unlocked }

  var stops: [PackStop] { days.flatMap(\.stops) }

  /// How many stops the map cannot show; the page says so under it.
  var unplacedCount: Int { max(stops.count - points.count, 0) }

  /// The days as the shared result components group them: the server's
  /// 1-based day as the label, the card ids unique per stop.
  var groups: [DayGroup] { days.map { DayGroup(number: $0.dayNumber, stops: $0.stops.map(\.card)) } }
}

/// The catalog's filters (web: packs/index.tsx, sent as `usePacks` sends them).
nonisolated struct PackFilters: Equatable, Hashable, Sendable {
  var theme: PackTheme?
  var month: Int?
  var onlyFree = false

  static let pageSize: Int32 = 24

  var isActive: Bool { theme != nil || month != nil || onlyFree }

  /// Unset filters are left unset, not sent as "" / 0 / false: the server
  /// treats a present field as a filter.
  var request: Loci_Bundle_V1_ListBundlesRequest {
    var request = Loci_Bundle_V1_ListBundlesRequest()
    if let theme { request.theme = theme.rawValue }
    if let month, (1...12).contains(month) { request.month = Int32(month) }
    if onlyFree { request.onlyFree = true }
    request.pagination.page = 1
    request.pagination.pageSize = Self.pageSize
    return request
  }
}

nonisolated struct PackPage: Equatable, Sendable {
  let packs: [PackSummary]
  let total: Int
}
