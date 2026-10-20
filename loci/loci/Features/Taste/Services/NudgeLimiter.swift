import Foundation

/// How often "you're near a saved place that fits you" may speak: at most
/// twice a local day, a place at most once a week, and never before 08:00 or
/// from 21:00.
nonisolated struct NudgeLimiter {
  static let perDay = 2
  static let firstHour = 8
  static let quietFromHour = 21
  static let placeCooldown: TimeInterval = 7 * 24 * 3600
  static let key = "loci_taste_nudges"

  private let defaults: UserDefaults
  private let calendar: Calendar

  init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
    self.defaults = defaults
    self.calendar = calendar
  }

  /// Whether a nudge for the place may go out now; a yes is recorded.
  func allow(poiID: String, now: Date = Date()) -> Bool {
    let hour = calendar.component(.hour, from: now)
    guard hour >= Self.firstHour, hour < Self.quietFromHour else { return false }
    var sent = (defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]).filter {
      now.timeIntervalSince1970 - $0.value < Self.placeCooldown
    }
    guard sent[poiID] == nil else { return false }
    let today = sent.values.filter { calendar.isDate(Date(timeIntervalSince1970: $0), inSameDayAs: now) }.count
    guard today < Self.perDay else { return false }
    sent[poiID] = now.timeIntervalSince1970
    defaults.set(sent, forKey: Self.key)
    return true
  }
}
