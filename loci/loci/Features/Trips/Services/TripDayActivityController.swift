@preconcurrency import ActivityKit
import CoreLocation
import Foundation
import LociConnectProto
import Observation
import UserNotifications

/// Runs one trip day as a Live Activity. The schedule (DayTimeline) decides
/// the current stop; a tap on Next or a geofence hit moves ahead of it until
/// the schedule catches up. Nothing here needs the server.
@Observable @MainActor final class TripDayActivityController {
  static let shared = TripDayActivityController()

  struct Running: Equatable {
    let tripId: String
    let dayId: String
    let cityName: String
    let startedAt: Date
    let slots: [TimelineSlot]
  }

  /// "tripId|dayId|startedAt", what UserDefaults keeps across a relaunch.
  nonisolated struct RunningRecord: Equatable, Sendable {
    let tripId: String
    let dayId: String
    let startedAt: Date

    init(tripId: String, dayId: String, startedAt: Date) {
      self.tripId = tripId
      self.dayId = dayId
      self.startedAt = startedAt
    }

    init?(raw: String) {
      let parts = raw.split(separator: "|").map(String.init)
      guard parts.count == 3, let seconds = TimeInterval(parts[2]) else { return nil }
      self.init(tripId: parts[0], dayId: parts[1], startedAt: Date(timeIntervalSince1970: seconds))
    }

    var raw: String { "\(tripId)|\(dayId)|\(startedAt.timeIntervalSince1970)" }
  }

  nonisolated static let endAfterLast: TimeInterval = 30 * 60
  nonisolated static let maxDuration: TimeInterval = 12 * 3600
  nonisolated static let notificationCategory = "tripDay"
  private static let runningKey = "loci_trip_day_running"  // "tripId|dayId|startedAt"

  private(set) var running: Running?
  private(set) var manualIndex: Int?
  private var activity: Activity<TripDayAttributes>?
  private let fences = POIProximityMonitor(name: POIProximityMonitor.tripDayName)

  var isRunning: Bool { running != nil }
  var liveActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

  init() {
    fences.onArrive = { [weak self] identifier in
      Task { await self?.arrived(at: identifier) }
    }
  }

  func start(trip: Loci_Trip_TripDraft, day: Loci_Trip_TripDay, now: Date = Date()) async {
    await end()  // this one, and any left over from a relaunch
    let dayStart = trip.constraints.hasDayStartMinute ? Int(trip.constraints.dayStartMinute) : nil
    let slots = DayTimeline.slots(day: day, legs: trip.legs, dayStartMinute: dayStart)
    guard !slots.isEmpty else { return }
    let cityName = day.cityName.isEmpty ? trip.cityName : day.cityName
    let run = Running(tripId: trip.id, dayId: day.id, cityName: cityName, startedAt: now, slots: slots)
    running = run
    manualIndex = nil
    let attributes = TripDayAttributes(tripId: trip.id, dayId: day.id, cityName: cityName, stopCount: slots.count, startedAt: now)
    let (state, _) = Self.state(slots: slots, manualIndex: nil, startedAt: now, now: now)
    activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: state.slotEnd), pushType: nil)
    UserDefaults.standard.set(RunningRecord(tripId: trip.id, dayId: day.id, startedAt: now).raw, forKey: Self.runningKey)
    await fences.arm(places: Self.fenceable(slots), from: slots.first?.coordinate)
    await scheduleReminders(slots)
  }

  /// Move to the next stop ahead of the schedule.
  func advance(now: Date = Date()) async {
    guard let running else { return }
    let current = Self.effectiveIndex(slots: running.slots, manualIndex: manualIndex, now: now)
    manualIndex = min(current + 1, running.slots.count)
    await refresh(now: now)
  }

  /// A reminder tap: move to the stop it named, never past it, and only for
  /// the day that is running.
  func advance(toReminder index: Int, tripId: String, dayId: String, now: Date = Date()) async {
    guard let running, running.tripId == tripId, running.dayId == dayId else { return }
    manualIndex = Self.manualIndex(afterReminderFor: index, current: manualIndex, slots: running.slots, now: now)
    await refresh(now: now)
  }

  /// Recompute the activity from the clock; ends it when the day is over.
  func refresh(now: Date = Date()) async {
    guard let running else { return }
    let (state, shouldEnd) = Self.state(slots: running.slots, manualIndex: manualIndex, startedAt: running.startedAt, now: now)
    if shouldEnd {
      await end(final: state)
      return
    }
    if let activity {
      await activity.update(ActivityContent(state: state, staleDate: state.slotEnd))
    }
  }

  /// On scene active: pick the activity back up after a relaunch, then let
  /// the clock move it (or end it) — the schedule only drives it while the
  /// app runs.
  func refreshOrAdopt(now: Date = Date()) async {
    if running == nil { await adoptFromCache() }
    await refresh(now: now)
  }

  /// End this day's activity and any other trip-day activity the system
  /// still holds (a relaunch can leave one behind).
  func end(final: TripDayAttributes.ContentState? = nil) async {
    for live in Activity<TripDayAttributes>.activities {
      let last = final ?? live.content.state
      await live.end(ActivityContent(state: last, staleDate: nil), dismissalPolicy: .default)
    }
    activity = nil
    running = nil
    manualIndex = nil
    UserDefaults.standard.removeObject(forKey: Self.runningKey)
    await fences.disarm()
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.reminderIDs)
  }

  /// Re-adopt an activity that survived a relaunch, from the trips given.
  /// The record is kept while the trip is not at hand (an empty or offline
  /// list), and dropped only when the system no longer holds the activity.
  func adoptIfRunning(trips: [Loci_Trip_TripDraft]) async {
    guard running == nil, let raw = UserDefaults.standard.string(forKey: Self.runningKey), let record = RunningRecord(raw: raw) else { return }
    guard let live = Activity<TripDayAttributes>.activities.first(where: { $0.attributes.dayId == record.dayId }) else {
      UserDefaults.standard.removeObject(forKey: Self.runningKey)
      return
    }
    guard let trip = trips.first(where: { $0.id == record.tripId }), let day = trip.days.first(where: { $0.id == record.dayId }) else { return }
    activity = live
    let dayStart = trip.constraints.hasDayStartMinute ? Int(trip.constraints.dayStartMinute) : nil
    let slots = DayTimeline.slots(day: day, legs: trip.legs, dayStartMinute: dayStart)
    running = Running(
      tripId: trip.id,
      dayId: day.id,
      cityName: day.cityName.isEmpty ? trip.cityName : day.cityName,
      startedAt: record.startedAt,
      slots: slots
    )
    await fences.arm(places: Self.fenceable(slots), from: slots.first?.coordinate)
    await refresh()
  }

  /// The same, from the phone's cached trips, for a launch that does not
  /// visit the trips list (a reminder tap into the editor).
  private func adoptFromCache() async {
    guard let raw = UserDefaults.standard.string(forKey: Self.runningKey), let record = RunningRecord(raw: raw) else { return }
    var trips = await LocalCache.shared.get(Loci_Trip_ListTripsResponse.self, kind: .trips, id: "all")?.value.trips ?? []
    if let single = await LocalCache.shared.get(Loci_Trip_TripDraft.self, kind: .trip, id: record.tripId)?.value { trips.append(single) }
    await adoptIfRunning(trips: trips)
  }

  /// A fence around the next stop fired: the traveller got there early.
  private func arrived(at identifier: String) async {
    guard let running else { return }
    let index = Self.effectiveIndex(slots: running.slots, manualIndex: manualIndex, now: Date())
    guard let next = running.slots.first(where: { $0.index == index + 1 }), next.stop.poi.stableID == identifier else { return }
    await advance()
  }

  // MARK: - Pure

  /// The slot index the activity shows: the manual override while it is ahead
  /// of the schedule, else the schedule.
  nonisolated static func effectiveIndex(slots: [TimelineSlot], manualIndex: Int?, now: Date) -> Int {
    let scheduled = DayTimeline.current(slots, at: now)?.index ?? -1
    return max(scheduled, manualIndex ?? -1)
  }

  /// Where a reminder for slot `index` leaves the manual override: at that
  /// stop, unless the schedule or an earlier tap is already past it.
  nonisolated static func manualIndex(afterReminderFor index: Int, current: Int?, slots: [TimelineSlot], now: Date) -> Int? {
    let scheduled = DayTimeline.current(slots, at: now)?.index ?? -1
    return max(index, current ?? -1, scheduled)
  }

  nonisolated static func state(
    slots: [TimelineSlot], manualIndex: Int?, startedAt: Date, now: Date
  ) -> (TripDayAttributes.ContentState, shouldEnd: Bool) {
    let count = slots.count
    let index = effectiveIndex(slots: slots, manualIndex: manualIndex, now: now)
    let lastEnd = slots.last?.end ?? startedAt
    let expired = now > lastEnd.addingTimeInterval(endAfterLast) || now > startedAt.addingTimeInterval(maxDuration)
    if index >= count || expired {
      let last = slots.last
      let done = TripDayAttributes.ContentState(
        phase: .done, currentIndex: max(count - 1, 0), currentName: last?.stop.name ?? "", slotEnd: now, stopsDone: count
      )
      return (done, true)
    }
    if index < 0 {
      let first = slots[0]
      let waiting = TripDayAttributes.ContentState(
        phase: .beforeFirst, currentIndex: 0, currentName: first.stop.name, slotEnd: first.start, nextName: first.stop.name, stopsDone: 0
      )
      return (waiting, false)
    }
    let slot = slots[index]
    let next = DayTimeline.next(slots, after: slot)
    let between = now > slot.end && manualIndex == nil
    let state = TripDayAttributes.ContentState(
      phase: between ? .between : .atStop,
      currentIndex: index,
      currentName: slot.stop.name,
      slotEnd: between ? (next?.start ?? slot.end) : slot.end,
      nextName: next?.stop.name,
      nextDistanceMeters: slot.distanceToNextMeters,
      stopsDone: between ? index + 1 : index
    )
    return (state, false)
  }

  /// The stops a geofence can be put around.
  nonisolated static func fenceable(_ slots: [TimelineSlot]) -> [Loci_Poi_POIDetailedInfo] {
    slots.compactMap { $0.coordinate != nil && $0.stop.hasPoi ? $0.stop.poi : nil }
  }

  // MARK: - Reminders

  private static var reminderIDs: [String] { (0..<40).map { "trip-day-\($0)" } }

  /// "Time for <next stop>?" at the end of each slot; the tap advances.
  private func scheduleReminders(_ slots: [TimelineSlot]) async {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: Self.reminderIDs)
    guard let running else { return }
    for slot in slots.dropLast() {
      guard let next = DayTimeline.next(slots, after: slot), slot.end > Date() else { continue }
      let content = UNMutableNotificationContent()
      content.title = "Time for \(next.stop.name)?"
      content.body = "The plan moves on from \(slot.stop.name). Tap to advance."
      content.categoryIdentifier = Self.notificationCategory
      content.threadIdentifier = "trip-day"
      content.userInfo = ["tripId": running.tripId, "dayId": running.dayId, "index": next.index]
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(slot.end.timeIntervalSinceNow, 1), repeats: false)
      try? await center.add(UNNotificationRequest(identifier: "trip-day-\(slot.index)", content: content, trigger: trigger))
    }
  }
}
