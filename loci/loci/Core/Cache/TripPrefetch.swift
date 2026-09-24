import BackgroundTasks
import CoreLocation
import Foundation
import LociConnectProto
import SwiftProtobuf

/// Refreshes the next trip day's trip, forecast and money before the day
/// starts, so the phone has them with no signal. Best effort: iOS decides
/// when a BGAppRefreshTask runs; the foreground refresh on open is the
/// guarantee.
@MainActor enum TripPrefetch {
  static let taskID = "com.fernandocorreia.loci.trip-prefetch"
  static let staleAfter: TimeInterval = 3 * 3600

  static func register() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
      guard let task = task as? BGAppRefreshTask else { return }
      let work = Task { @MainActor in
        let done = await run()
        task.setTaskCompleted(success: done)
      }
      task.expirationHandler = { work.cancel() }
    }
  }

  /// Called after every trips load and every prefetch: one pending request at most.
  static func scheduleIfNeeded(trips: [Loci_Trip_TripDraft], now: Date = Date()) {
    guard let begin = nextBeginDate(trips: trips, now: now) else { return }
    let request = BGAppRefreshTaskRequest(identifier: taskID)
    request.earliestBeginDate = begin
    try? BGTaskScheduler.shared.submit(request)
  }

  /// 22:00 the evening before the next trip day within 48 h; on the day itself,
  /// six hours from now while that still falls inside the day.
  nonisolated static func nextBeginDate(trips: [Loci_Trip_TripDraft], now: Date, calendar: Calendar = .current) -> Date? {
    let horizon = now.addingTimeInterval(48 * 3600)
    let days = trips.flatMap(\.days).filter { !$0.travelDay }.compactMap { DayTimeline.localMidnight(of: $0, calendar: calendar) }
    let upcoming = days.filter { day in
      guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
      return day <= horizon && dayEnd > now
    }
    guard let day = upcoming.min() else { return nil }
    if calendar.isDate(day, inSameDayAs: now) {
      let candidate = now.addingTimeInterval(6 * 3600)
      return calendar.isDate(candidate, inSameDayAs: now) ? candidate : nil
    }
    guard let evening = calendar.date(byAdding: .hour, value: -2, to: day) else { return nil }
    return max(evening, now)
  }

  /// The work itself, also used by the foreground refresh. Refreshes the trip
  /// with a day today or tomorrow, then that day's forecast and rates.
  static func run() async -> Bool {
    guard let trips = await LocalCache.shared.get(Loci_Trip_ListTripsResponse.self, kind: .trips, id: "all")?.value.trips else { return true }
    let now = Date()
    let tomorrow = now.addingTimeInterval(24 * 3600)
    guard let trip = trips.first(where: { DayTimeline.today(in: $0, now: now) != nil || DayTimeline.today(in: $0, now: tomorrow) != nil }) else {
      return true
    }
    var request = Loci_Trip_GetTripRequest()
    request.tripID = trip.id
    let sent = request
    let fresh = try? await rpc("", sent) { await TripAPI.client.getTrip(request: $0, headers: [:]) }
    if let fresh { try? await LocalCache.shared.put(fresh, kind: .trip, id: trip.id) }
    let current = fresh ?? trip
    if let day = DayTimeline.today(in: current, now: now) ?? DayTimeline.today(in: current, now: tomorrow), let (lat, lon) = coordinate(of: day) {
      await refreshContext(latitude: lat, longitude: lon)
    }
    scheduleIfNeeded(trips: trips, now: now)
    return fresh != nil
  }

  /// On open: refresh today's forecast when the copy is older than three hours.
  static func refreshTodayIfStale() async {
    guard let trips = await LocalCache.shared.get(Loci_Trip_ListTripsResponse.self, kind: .trips, id: "all")?.value.trips,
      let day = trips.lazy.compactMap({ DayTimeline.today(in: $0) }).first, let (lat, lon) = coordinate(of: day)
    else { return }
    let key = LocalCache.key(latitude: lat, longitude: lon)
    if let copy = await LocalCache.shared.get(Loci_Localcontext_LocalContext.self, kind: .localContext, id: key),
      Date().timeIntervalSince(copy.fetchedAt) < staleAfter
    {
      return
    }
    _ = await run()
  }

  private static func refreshContext(latitude: Double, longitude: Double) async {
    let key = LocalCache.key(latitude: latitude, longitude: longitude)
    if let context = try? await ResultsAPI.localContext(latitude: latitude, longitude: longitude) {
      try? await LocalCache.shared.put(context, kind: .localContext, id: key)
    }
    if let fx = try? await ResultsAPI.fxRates(latitude: latitude, longitude: longitude) {
      try? await LocalCache.shared.put(fx, kind: .fx, id: key)
    }
  }

  /// The day's city centre, else its first stop with a pin.
  nonisolated static func coordinate(of day: Loci_Trip_TripDay) -> (Double, Double)? {
    if day.hasCityLat, day.hasCityLon { return (day.cityLat, day.cityLon) }
    if let c = day.stops.lazy.compactMap(DayTimeline.coordinate(of:)).first { return (c.latitude, c.longitude) }
    return nil
  }
}
