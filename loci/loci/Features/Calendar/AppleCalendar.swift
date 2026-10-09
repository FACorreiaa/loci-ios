import EventKit
import Foundation
import LociConnectProto
import SwiftProtobuf

/// Device-local Apple Calendar. No server tokens — EventKit only.
@MainActor public final class AppleCalendar {
  public static let shared = AppleCalendar()
  public static let lociCalendarTitle = "Loci"

  private let store = EKEventStore()

  public var authorizationStatus: EKAuthorizationStatus {
    EKEventStore.authorizationStatus(for: .event)
  }

  public var isAuthorized: Bool { authorizationStatus == .fullAccess }

  public func requestAccess() async throws -> Bool {
    try await store.requestFullAccessToEvents()
  }

  public func events(from start: Date, to end: Date) -> [EKEvent] {
    guard isAuthorized else { return [] }
    let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    return store.events(matching: pred)
  }

  /// One event per dated day. Writing the same trip again replaces its events
  /// rather than adding a second set: each carries the trip's `loci://trips/<id>`
  /// link, and the Loci calendar's events with that link go first.
  public func writeTrip(_ trip: Loci_Trip_TripDraft) throws {
    guard isAuthorized else { throw APIError.custom("Calendar access was not granted.") }
    let cal = try lociCalendar()
    let link = trip.id.isEmpty ? nil : URL(string: "loci://trips/\(trip.id)")
    let days = trip.days.filter(\.hasDate)
    let dates = days.map { Date(timeIntervalSince1970: TimeInterval($0.date.seconds)) }
    do {
      if let link {
        for old in events(linkedTo: link, in: cal, around: dates) { try store.remove(old, span: .thisEvent, commit: false) }
      }
      for (day, start) in zip(days, dates) {
        let event = EKEvent(eventStore: store)
        event.calendar = cal
        event.title = trip.title.isEmpty ? (trip.cityName.isEmpty ? "Loci trip" : "Trip to \(trip.cityName)") : trip.title
        event.startDate = start
        event.endDate = start.addingTimeInterval(8 * 60 * 60)
        event.isAllDay = day.stops.isEmpty
        event.location = day.cityName.isEmpty ? trip.cityName : day.cityName
        event.notes = "Day \(day.dayNumber) · Loci"
        event.url = link
        try store.save(event, span: .thisEvent, commit: false)
      }
      try store.commit()
    } catch {
      store.reset()
      throw error
    }
  }

  /// Events this app wrote for a trip, searched a year either side of its
  /// dates (and today), since re-pinned days may have moved.
  private func events(linkedTo link: URL, in cal: EKCalendar, around dates: [Date]) -> [EKEvent] {
    let now = Date()
    let year: TimeInterval = 365 * 24 * 60 * 60
    let start = min(dates.min() ?? now, now).addingTimeInterval(-year)
    let end = max(dates.max() ?? now, now).addingTimeInterval(year)
    let pred = store.predicateForEvents(withStart: start, end: end, calendars: [cal])
    return store.events(matching: pred).filter { $0.url == link }
  }

  /// One event per stop, timed by `CalendarSchedule` (web's `.ics` from the
  /// Trip Kit). Returns how many events were written.
  @discardableResult func writeStops(_ events: [StopEvent]) throws -> Int {
    guard isAuthorized else { throw APIError.custom("Calendar access was not granted.") }
    let cal = try lociCalendar()
    for stop in events {
      let event = EKEvent(eventStore: store)
      event.calendar = cal
      event.title = stop.title
      event.startDate = stop.start
      event.endDate = stop.end
      event.location = stop.location
      event.notes = stop.notes.isEmpty ? "Loci" : "\(stop.notes)\n\nLoci"
      try store.save(event, span: .thisEvent, commit: false)
    }
    try store.commit()
    return events.count
  }

  private func lociCalendar() throws -> EKCalendar {
    if let existing = store.calendars(for: .event).first(where: { $0.title == Self.lociCalendarTitle }) {
      return existing
    }
    guard let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first(where: { $0.sourceType == .local }) else {
      throw APIError.custom("No calendar source is available on this device.")
    }
    let cal = EKCalendar(for: .event, eventStore: store)
    cal.title = Self.lociCalendarTitle
    cal.source = source
    try store.saveCalendar(cal, commit: true)
    return cal
  }
}
