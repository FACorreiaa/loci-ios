import Foundation
import LociConnectProto

/// "Today" on a trip (web: lib/dashboard/today.ts): which planned day it is
/// and the stop to head for next. When a trip covers today, Discover leads
/// with it instead of the prompt box.
nonisolated struct TodayFirst: Sendable {
  let trip: Loci_Trip_TripDraft
  let day: Loci_Trip_TripDay
  /// The first stop still ahead by start time, else the day's first stop.
  let next: Loci_Trip_TripStop?

  /// Today's day across trips; with overlapping trips, the one that started last.
  static func pick(trips: [Loci_Trip_TripDraft], now: Date = Date(), calendar: Calendar = .current) -> TodayFirst? {
    trips
      .compactMap { trip -> (TodayFirst, Date)? in
        guard let day = DayTimeline.today(in: trip, now: now, calendar: calendar) else { return nil }
        let start = trip.days.compactMap { DayTimeline.localMidnight(of: $0, calendar: calendar) }.min() ?? .distantPast
        return (TodayFirst(trip: trip, day: day, next: nextStop(in: day, now: now, calendar: calendar)), start)
      }
      .max { $0.1 < $1.1 }?.0
  }

  static func nextStop(in day: Loci_Trip_TripDay, now: Date, calendar: Calendar) -> Loci_Trip_TripStop? {
    let ordered = day.stops.sorted { $0.orderIndex < $1.orderIndex }
    let parts = calendar.dateComponents([.hour, .minute], from: now)
    let minute = Int32((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    return ordered.first { $0.hasStartMinute && $0.startMinute >= minute } ?? ordered.first
  }
}
