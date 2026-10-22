import Accessibility
import CoreLocation
import Foundation
import LociConnectProto
import Observation
import UserNotifications

/// The "+10 · Visited Pantheon" chip, shown over the tabs for a moment when an
/// action earns points, and "Achievement unlocked" after it. Points replace
/// each other (only the newest shows); an unlock waits its turn.
@MainActor @Observable final class PointsFeedback {
  static let shared = PointsFeedback()

  struct Toast: Equatable, Identifiable {
    let id = UUID()
    let points: Int
    let label: String
    /// An unlock's medallion symbol; nil for points.
    var symbol: String?
  }

  private(set) var current: Toast?
  /// Unlocks waiting for the chip.
  private var queue: [Toast] = []
  /// Bumped when an award changes progress, so open progress views reload.
  private(set) var revision = 0

  func show(points: Int, label: String) {
    revision += 1
    guard points > 0 else { return }
    present(Toast(points: points, label: label))
    // The chip leaves before VoiceOver would reach it, so it is read out now.
    AccessibilityNotification.Announcement(AttributedString(localized: "^[\(points) point](inflect: true): \(label)")).post()
  }

  /// The best of what an action unlocked, as the server's push picks it: one
  /// chip, "(+2 more)" for the rest, after any points chip showing.
  func unlocked(_ achievements: [Loci_Achievement_Achievement]) {
    guard let best = achievements.best else { return }
    revision += 1
    let more = achievements.count > 1 ? " (+\(achievements.count - 1) more)" : ""
    let toast = Toast(points: 0, label: "Unlocked: \(best.label)\(more)", symbol: best.symbol)
    AccessibilityNotification.Announcement(AttributedString("Achievement unlocked: \(best.label)")).post()
    if current == nil { present(toast) } else { queue.append(toast) }
  }

  func dismiss() {
    current = nil
    if !queue.isEmpty { present(queue.removeFirst()) }
  }

  private func present(_ toast: Toast) {
    current = toast
    Task {
      try? await Task.sleep(for: .seconds(toast.symbol == nil ? 2.5 : 4))
      if current?.id == toast.id { dismiss() }
    }
  }
}

/// Points side effects of things the app already does. Each is best effort:
/// a failure is logged, never shown, and never undoes the action itself.
nonisolated enum ProgressReporter {
  private static let checkInKey = "loci_last_check_in_day"

  /// The day's check-in, once per local day; the server is idempotent too, so
  /// this only saves a round trip.
  @MainActor static func checkInIfNeeded(now: Date = Date()) async {
    let today = Self.dayKey(now)
    guard UserDefaults.standard.string(forKey: checkInKey) != today else { return }
    do {
      let response = try await ProgressAPI.checkIn()
      UserDefaults.standard.set(today, forKey: checkInKey)
      PointsFeedback.shared.show(points: Int(response.pointsAwarded), label: "Daily check-in")
      if response.pointsAwarded > 0 { Analytics.capture(.pointsAwarded, ["kind": "check_in", "points": Int(response.pointsAwarded)]) }
      if let field = try? await ProgressAPI.fieldProfile() { await StreakReminder.schedule(after: field.weekStreak, now: now) }
    } catch {
      // Tried again on the next foreground; the day is not marked done.
    }
  }

  /// A place reached on the spot. Needs a recent fix: the server scores only a
  /// visit the phone was actually at.
  static func arrived(_ visit: SpotVisit, location: CLLocation?) {
    guard let location, !visit.cityName.isEmpty else { return }
    Task { @MainActor in
      // Asked later: on arrival the traveller has only just got there.
      RatePrompter.shared.enqueueArrival(poiID: visit.poiID, name: visit.poiName, cityName: visit.cityName, category: "")
    }
    Task {
      do {
        let points = try await ProgressAPI.recordVisit(visit, at: location)
        await MainActor.run {
          PointsFeedback.shared.show(points: points, label: "Visited \(visit.poiName)")
          if points > 0 { Analytics.capture(.pointsAwarded, ["kind": "visit", "points": points]) }
        }
      } catch {
        // Best effort: the walk goes on without the points.
      }
    }
  }

  /// A trip day walked to its end.
  static func walked(tripID: String, dayID: String, stopsDone: Int) {
    guard stopsDone > 0, !tripID.isEmpty, !dayID.isEmpty else { return }
    Task {
      do {
        let response = try await ProgressAPI.completeTripDay(tripID: tripID, dayID: dayID, stopsDone: stopsDone)
        let label = response.tripCompleted ? "Trip finished" : "Day walked"
        let points = Int(response.pointsAwarded)
        await MainActor.run {
          PointsFeedback.shared.show(points: points, label: label)
          PointsFeedback.shared.unlocked(response.unlocked)
          if points > 0 { Analytics.capture(.pointsAwarded, ["kind": "trip_day", "points": points]) }
        }
      } catch {
        // Best effort: the day stays walked on the phone.
      }
    }
  }

  static func dayKey(_ date: Date) -> String {
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
}

/// The Sunday-evening nudge before a weekly streak breaks. Local, so it never
/// needs the server at fire time: after each check-in the next reminder is
/// replaced, from the Field profile's week streak.
nonisolated enum StreakReminder {
  static let identifier = "loci_streak_reminder"
  static let enabledKey = "loci_streak_reminders"
  /// Sunday 18:00 local: the streak's week (ISO, Monday to Sunday) ends at midnight.
  static let weekday = 1
  static let hour = 18

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
  }

  static func schedule(after streak: Loci_Gamification_WeekStreak, now: Date = Date()) async {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    guard isEnabled, let when = fireDate(after: streak, now: now) else { return }
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
    let content = UNMutableNotificationContent()
    content.title = "Keep your \(streak.current)-week streak"
    content.body = "Save a place or walk a stop today so your streak doesn't reset."
    content.threadIdentifier = "progress"
    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
    let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
  }

  /// This week's Sunday evening when the week still needs exploring; next
  /// week's once it is done (the next check-in moves it again). Nil without a streak.
  static func fireDate(after streak: Loci_Gamification_WeekStreak, now: Date, calendar: Calendar = .current) -> Date? {
    guard streak.current > 0 else { return nil }
    let evening = DateComponents(hour: hour, minute: 0, weekday: weekday)
    guard let thisSunday = calendar.nextDate(after: now, matching: evening, matchingPolicy: .nextTime) else { return nil }
    // A Sunday reminder belongs to the week ending that day; past its hour, the next Sunday is next week's.
    guard streak.exploredThisWeek else { return thisSunday }
    let daysToSunday = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: thisSunday)).day ?? 0
    // Already explored this week: remind at the end of the next one.
    return daysToSunday >= 7 ? thisSunday : calendar.date(byAdding: .day, value: 7, to: thisSunday)
  }

  static func setEnabled(_ on: Bool) {
    UserDefaults.standard.set(on, forKey: enabledKey)
    if !on { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier]) }
  }
}
