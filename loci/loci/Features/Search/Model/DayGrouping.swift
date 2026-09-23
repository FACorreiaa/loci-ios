import CoreLocation
import Foundation
import LociConnectProto

/// One day of a result page: the web `groupStopsByDay` rule (lib/trip-kit.ts).
/// Groups are labelled by position ("Day 1" is the first group), not by the
/// server's day value, and stops without a day only exist when no stop has one.
nonisolated struct DayGroup: Equatable, Sendable {
  /// 1-based label.
  let number: Int
  let stops: [Loci_Poi_POIDetailedInfo]
}

nonisolated enum DayGrouping {
  /// Web's `STOPS_PER_DAY`: the fallback when the server assigned no days.
  static let stopsPerDay = 4
  /// Web's `INITIAL_DAYS`: how many days open before "Show the rest".
  static let initialDays = 2

  /// Itinerary stops in server order: `(day, priority)` like `stopsFromCityResponse`.
  static func ordered(_ stops: [Loci_Poi_POIDetailedInfo]) -> [Loci_Poi_POIDetailedInfo] {
    stops.enumerated().sorted { a, b in
      let dayA = a.element.hasDay ? Int(a.element.day) : Int.max
      let dayB = b.element.hasDay ? Int(b.element.day) : Int.max
      if dayA != dayB { return dayA < dayB }
      let priorityA = a.element.hasPriority ? Int(a.element.priority) : 999
      let priorityB = b.element.hasPriority ? Int(b.element.priority) : 999
      if priorityA != priorityB { return priorityA < priorityB }
      return a.offset < b.offset
    }.map(\.element)
  }

  /// Group by the server's 1-based `day` when any stop has one; otherwise chunk.
  static func groups(_ stops: [Loci_Poi_POIDetailedInfo]) -> [DayGroup] {
    let sorted = ordered(stops)
    guard sorted.contains(where: \.hasDay) else {
      return stride(from: 0, to: sorted.count, by: stopsPerDay).enumerated().map { index, start in
        DayGroup(number: index + 1, stops: Array(sorted[start..<min(start + stopsPerDay, sorted.count)]))
      }
    }
    var byDay: [Int: [Loci_Poi_POIDetailedInfo]] = [:]
    var order: [Int] = []
    for stop in sorted {
      let day = stop.hasDay ? Int(stop.day) : Int.max
      if byDay[day] == nil { order.append(day) }
      byDay[day, default: []].append(stop)
    }
    return order.sorted().enumerated().map { index, day in DayGroup(number: index + 1, stops: byDay[day] ?? []) }
  }

  /// Top-level places that are not in the itinerary: web's "More to explore".
  static func extras(all: [Loci_Poi_POIDetailedInfo], itinerary: [Loci_Poi_POIDetailedInfo]) -> [Loci_Poi_POIDetailedInfo] {
    let inItinerary = Set(itinerary.map(\.stableID))
    var seen = Set<String>()
    return all.filter { !inItinerary.contains($0.stableID) && seen.insert($0.stableID).inserted }
  }

  /// The running index of every stop, across days, 1-based (web's `seq`).
  static func sequence(_ groups: [DayGroup]) -> [String: Int] {
    var result: [String: Int] = [:]
    var index = 0
    for group in groups {
      for stop in group.stops {
        index += 1
        result[stop.stableID] = index
      }
    }
    return result
  }
}

// MARK: - Share text (web: lib/share.ts buildShareText)

nonisolated enum ShareText {
  static let signature = "Generated from Loci"
  static let homeURL = "https://lociai.fyi"
  static let maxNamesPerDay = 4
  static let maxDays = 4

  static func build(title: String, groups: [DayGroup], description: String? = nil) -> String {
    var lines = [title]
    if !groups.isEmpty {
      for group in groups.prefix(maxDays) {
        let names = group.stops.map(\.name)
        let shown = names.prefix(maxNamesPerDay).joined(separator: ", ")
        let rest = names.count - maxNamesPerDay
        lines.append("Day \(group.number) · \(shown)" + (rest > 0 ? " +\(rest) more" : ""))
      }
      let restDays = groups.count - maxDays
      if restDays > 0 { lines.append("+\(restDays) more day\(restDays == 1 ? "" : "s")") }
    } else if let description, !description.isEmpty {
      lines.append(description.count > 120 ? String(description.prefix(117)) + "…" : description)
    }
    lines.append("")
    lines.append(signature)
    lines.append(homeURL)
    return lines.joined(separator: "\n")
  }
}

// MARK: - Google Maps (web: lib/trip-kit.ts buildGoogleMapsMultiStopUrl)

nonisolated enum GoogleMapsRoute {
  static let maxWaypoints = 8

  static func url(for stops: [Loci_Poi_POIDetailedInfo], cityName: String) -> URL? {
    let usable = stops.filter { hasCoordinate($0) || !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    guard !usable.isEmpty else { return nil }
    func place(_ stop: Loci_Poi_POIDetailedInfo) -> String {
      if hasCoordinate(stop) { return "\(stop.latitude),\(stop.longitude)" }
      let query = [stop.name, stop.address, cityName].filter { !$0.isEmpty }.joined(separator: ", ")
      return query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? query
    }
    if usable.count == 1 {
      return URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(place(usable[0]))&travelmode=walking")
    }
    let via = usable.dropFirst().dropLast().prefix(maxWaypoints).map(place).joined(separator: "%7C")
    let waypoints = via.isEmpty ? "" : "&waypoints=\(via)"
    let origin = place(usable[0])
    let destination = place(usable[usable.count - 1])
    return URL(string: "https://www.google.com/maps/dir/?api=1&origin=\(origin)&destination=\(destination)\(waypoints)&travelmode=walking")
  }

  static func hasCoordinate(_ stop: Loci_Poi_POIDetailedInfo) -> Bool {
    stop.hasLatitude && stop.hasLongitude && (stop.latitude != 0 || stop.longitude != 0)
  }
}

nonisolated extension CharacterSet {
  /// RFC 3986 unreserved plus what `encodeURIComponent` leaves alone.
  static let urlQueryValueAllowed: CharacterSet = {
    var set = CharacterSet.alphanumerics
    set.insert(charactersIn: "-_.!~*'()")
    return set
  }()
}

// MARK: - Calendar schedule (web: lib/trip-kit.ts buildItineraryIcs)

/// One calendar event for a stop, timed like web's `.ics`: each day starts at
/// 09:00 on the chosen start date plus the day offset, stops run back to back
/// with a 15-minute buffer, and a stop without a known duration takes 90 minutes.
nonisolated struct StopEvent: Equatable, Sendable {
  let title: String
  let start: Date
  let end: Date
  let location: String
  let notes: String
}

nonisolated enum CalendarSchedule {
  static let dayStartHour = 9
  static let defaultMinutes = 90
  static let bufferMinutes = 15
  static let minMinutes = 30
  static let maxMinutes = 240

  static func events(
    groups: [DayGroup],
    startDate: Date,
    cityName: String,
    summary: String,
    calendar: Calendar = .current
  ) -> [StopEvent] {
    var events: [StopEvent] = []
    for (dayIndex, group) in groups.enumerated() {
      guard let dayDate = calendar.date(byAdding: .day, value: dayIndex, to: calendar.startOfDay(for: startDate)),
        var cursor = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: dayDate)
      else { continue }
      for stop in group.stops {
        let minutes = duration(for: stop)
        let end = cursor.addingTimeInterval(TimeInterval(minutes * 60))
        let location: String
        if !stop.address.isEmpty {
          location = stop.address
        } else if GoogleMapsRoute.hasCoordinate(stop) {
          location = "\(stop.latitude),\(stop.longitude)"
        } else {
          location = "\(stop.name), \(cityName)"
        }
        let blurb = stop.hasDescriptionPoi ? stop.descriptionPoi : stop.description_p
        let notes = [blurb, stop.category].filter { !$0.isEmpty }.joined(separator: " · ")
        events.append(StopEvent(title: stop.name, start: cursor, end: end, location: location, notes: notes.isEmpty ? summary : notes))
        cursor = end.addingTimeInterval(TimeInterval(bufferMinutes * 60))
      }
    }
    return events
  }

  /// The proto carries no time-to-spend, so every stop gets the default,
  /// clamped like web's `parseDurationMinutes` would clamp a parsed value.
  static func duration(for stop: Loci_Poi_POIDetailedInfo) -> Int {
    min(max(defaultMinutes, minMinutes), maxMinutes)
  }

  /// Web's default: tomorrow.
  static func defaultStartDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
    calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
  }
}

// MARK: - Pro gate (web: lib/subscription.ts isProPlan, TripKit unlockedStops)

nonisolated enum ProGate {
  static let proPlans: Set<String> = ["premium_monthly", "premium_annual", "premium", "pro", "paid", "explorer"]

  static func isPro(plan: String?) -> Bool {
    guard let plan = plan?.lowercased(), !plan.isEmpty else { return false }
    return proPlans.contains(plan)
  }

  /// Free plans export Day 1 only.
  static func unlocked(_ groups: [DayGroup], isPro: Bool) -> [DayGroup] { isPro ? groups : Array(groups.prefix(1)) }
}
