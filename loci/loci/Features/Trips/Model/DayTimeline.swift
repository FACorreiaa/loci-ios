import CoreLocation
import Foundation
import LociConnectProto
import SwiftProtobuf

/// One stop with the time it occupies on a trip day.
nonisolated struct TimelineSlot: Equatable, Sendable {
  let stop: Loci_Trip_TripStop
  let index: Int
  let start: Date
  let end: Date
  let coordinate: CLLocationCoordinate2D?
  let distanceToNextMeters: Double?

  static func == (lhs: TimelineSlot, rhs: TimelineSlot) -> Bool {
    lhs.stop.id == rhs.stop.id && lhs.index == rhs.index && lhs.start == rhs.start && lhs.end == rhs.end
  }
}

/// A trip day as a schedule. Stops with `start_minute` start then; the rest
/// follow the previous slot plus the buffer. Durations come from
/// `duration_minutes`, else the Trip Kit default, clamped like it.
nonisolated enum DayTimeline {
  /// `dayStartMinute` is the trip's `constraints.day_start_minute` (the
  /// daily active window), when set.
  static func slots(
    day: Loci_Trip_TripDay, legs: [Loci_Trip_TripLeg], dayStartMinute: Int? = nil, calendar: Calendar = .current
  ) -> [TimelineSlot] {
    guard let midnight = localMidnight(of: day, calendar: calendar) else { return [] }
    let dayStart = dayStartMinute ?? CalendarSchedule.dayStartHour * 60
    var cursor = midnight.addingTimeInterval(TimeInterval(dayStart * 60))
    var slots: [TimelineSlot] = []
    for (index, stop) in day.stops.enumerated() {
      let start = stop.hasStartMinute ? midnight.addingTimeInterval(TimeInterval(Int(stop.startMinute) * 60)) : cursor
      let wanted = stop.hasDurationMinutes ? Int(stop.durationMinutes) : CalendarSchedule.defaultMinutes
      let minutes = min(max(wanted, CalendarSchedule.minMinutes), CalendarSchedule.maxMinutes)
      let end = start.addingTimeInterval(TimeInterval(minutes * 60))
      let next = index + 1 < day.stops.count ? day.stops[index + 1] : nil
      let slot = TimelineSlot(
        stop: stop,
        index: index,
        start: start,
        end: end,
        coordinate: coordinate(of: stop),
        distanceToNextMeters: next.flatMap { distance(from: stop, to: $0, legs: legs) }
      )
      slots.append(slot)
      cursor = end.addingTimeInterval(TimeInterval(CalendarSchedule.bufferMinutes * 60))
    }
    return slots
  }

  /// The first non-travel day dated today in the phone's calendar.
  static func today(in trip: Loci_Trip_TripDraft, now: Date = Date(), calendar: Calendar = .current) -> Loci_Trip_TripDay? {
    trip.days.first { day in
      guard let midnight = localMidnight(of: day, calendar: calendar) else { return false }
      return !day.travelDay && calendar.isDate(midnight, inSameDayAs: now)
    }
  }

  /// A trip day's date is a calendar date carried as a timestamp: web writes
  /// midnight UTC, and the app's Calendar pin used to write local midnight.
  /// Round to the nearest UTC midnight (right for any offset under 12 h),
  /// read the date in UTC, and place it at midnight in the phone's calendar,
  /// or a traveller east or west of UTC sees the day one day off.
  static func localMidnight(of day: Loci_Trip_TripDay, calendar: Calendar = .current) -> Date? {
    guard day.hasDate else { return nil }
    let seconds = (day.date.date.timeIntervalSince1970 / 86_400).rounded() * 86_400
    let parts = utcCalendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: seconds))
    return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
  }

  /// What the app writes when it pins a trip: midnight UTC of the calendar
  /// day that contains `date` in the phone's calendar, the shape web writes.
  static func utcMidnight(ofDayContaining date: Date, calendar: Calendar = .current) -> Date? {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return utcCalendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
  }

  private static var utcCalendar: Calendar {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC") ?? .current
    return utc
  }

  /// The slot containing `at`, else the latest one that has started.
  static func current(_ slots: [TimelineSlot], at: Date) -> TimelineSlot? {
    slots.last { $0.start <= at }
  }

  static func next(_ slots: [TimelineSlot], after slot: TimelineSlot) -> TimelineSlot? {
    slots.first { $0.index == slot.index + 1 }
  }

  static func coordinate(of stop: Loci_Trip_TripStop) -> CLLocationCoordinate2D? {
    guard stop.hasPoi, stop.poi.hasLatitude, stop.poi.hasLongitude, stop.poi.latitude != 0 || stop.poi.longitude != 0 else { return nil }
    return CLLocationCoordinate2D(latitude: stop.poi.latitude, longitude: stop.poi.longitude)
  }

  private static func distance(from a: Loci_Trip_TripStop, to b: Loci_Trip_TripStop, legs: [Loci_Trip_TripLeg]) -> Double? {
    if let leg = legs.first(where: { $0.fromName == a.name && $0.toName == b.name }), leg.distanceKm > 0 {
      return leg.distanceKm * 1000
    }
    guard let ca = coordinate(of: a), let cb = coordinate(of: b) else { return nil }
    return CLLocation(latitude: ca.latitude, longitude: ca.longitude).distance(from: CLLocation(latitude: cb.latitude, longitude: cb.longitude))
  }
}
