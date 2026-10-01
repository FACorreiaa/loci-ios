import CoreLocation
import Foundation
import LociConnectProto
import Observation
import UserNotifications

/// The "+10 · Visited Pantheon" chip, shown over the tabs for a moment when an
/// action earns points. Only the newest one shows.
@MainActor @Observable final class PointsFeedback {
  static let shared = PointsFeedback()

  struct Toast: Equatable, Identifiable {
    let id = UUID()
    let points: Int
    let label: String
  }

  private(set) var current: Toast?
  /// Bumped when an award changes progress, so open progress views reload.
  private(set) var revision = 0

  func show(points: Int, label: String) {
    revision += 1
    guard points > 0 else { return }
    let toast = Toast(points: points, label: label)
    current = toast
    Task {
      try? await Task.sleep(for: .seconds(2.5))
      if current?.id == toast.id { current = nil }
    }
  }

  func dismiss() { current = nil }
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
      for badge in response.newBadges { PointsFeedback.shared.show(points: 0, label: "Badge: \(badge.title)") }
      await StreakReminder.schedule(after: response.progress, now: now)
    } catch {
      // Tried again on the next foreground; the day is not marked done.
    }
  }

  /// A place reached on the spot. Needs a recent fix: the server scores only a
  /// visit the phone was actually at.
  static func arrived(_ visit: SpotVisit, location: CLLocation?) {
    guard let location, !visit.cityName.isEmpty else { return }
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

/// The evening nudge before a streak breaks. Local, so it never needs the
/// server: after each check-in the next evening's reminder is replaced.
nonisolated enum StreakReminder {
  static let identifier = "loci_streak_reminder"
  static let enabledKey = "loci_streak_reminders"
  /// 19:00 local: late enough to have done something, early enough to act.
  static let hour = 19

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
  }

  static func schedule(after progress: Loci_Gamification_Progress, now: Date = Date()) async {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    guard isEnabled, progress.currentStreak > 0 else { return }
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
    guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return }
    var when = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
    when.hour = hour
    let content = UNMutableNotificationContent()
    content.title = "Keep your \(progress.currentStreak + 1)-day streak"
    content.body = "Open Loci today so your streak doesn't reset."
    content.threadIdentifier = "progress"
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
    try? await center.add(request)
  }

  static func setEnabled(_ on: Bool) {
    UserDefaults.standard.set(on, forKey: enabledKey)
    if !on { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier]) }
  }
}
