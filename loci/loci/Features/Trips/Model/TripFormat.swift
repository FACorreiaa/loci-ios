import Foundation
import LociConnectProto
import SwiftProtobuf

/// The trip page's display helpers (web: lib/trip-format.ts).
nonisolated enum TripFormat {
  /// "Route · 3 days" above the hero title (web: TripHero).
  static func heroEyebrow(dayCount: Int) -> String {
    "Route · \(dayCount) day\(dayCount == 1 ? "" : "s")"
  }

  // MARK: - Dates

  /// "4–6 Oct" style range across a trip's days (web: formatTripDates). Undated
  /// days are skipped; a trip with no dates at all gets nil rather than a
  /// fabricated range. Each day's date is read by `DayTimeline.localMidnight`,
  /// the same reading as the Today band, so midnight-UTC (web) and
  /// local-midnight (older app pins) dates both keep their calendar day.
  static func tripDates(_ days: [Loci_Trip_TripDay], calendar: Calendar = .current, locale: Locale = .current) -> String? {
    tripDates(days.compactMap { DayTimeline.localMidnight(of: $0, calendar: calendar) }, calendar: calendar, locale: locale)
  }

  static func tripDates(_ dates: [Date], calendar: Calendar = .current, locale: Locale = .current) -> String? {
    let sorted = dates.sorted()
    guard let first = sorted.first, let last = sorted.last else { return nil }
    var dayStyle = Date.FormatStyle(locale: locale, calendar: calendar).day()
    dayStyle.timeZone = calendar.timeZone
    var dayMonthStyle = Date.FormatStyle(locale: locale, calendar: calendar).day().month(.abbreviated)
    dayMonthStyle.timeZone = calendar.timeZone

    if calendar.isDate(first, inSameDayAs: last) { return first.formatted(dayMonthStyle) }
    let a = calendar.dateComponents([.year, .month], from: first)
    let b = calendar.dateComponents([.year, .month], from: last)
    if a.year == b.year, a.month == b.month {
      return "\(first.formatted(dayStyle))–\(last.formatted(dayMonthStyle))"
    }
    return "\(first.formatted(dayMonthStyle)) – \(last.formatted(dayMonthStyle))"
  }

  // MARK: - Minutes from midnight

  /// 570 → "09:30"; nil → "" (web: minutesToHHMM).
  static func minutesToHHMM(_ minutes: Int32?) -> String {
    guard let minutes else { return "" }
    return String(format: "%02d:%02d", minutes / 60, minutes % 60)
  }

  /// "09:30" → 570; empty or malformed → nil (web: hhmmToMinutes).
  static func hhmmToMinutes(_ value: String) -> Int32? {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, let hours = Int32(parts[0]), let minutes = Int32(parts[1]) else { return nil }
    return hours * 60 + minutes
  }

  /// A DatePicker's value for a minutes-from-midnight setting, on `reference`'s day.
  static func date(fromMinutes minutes: Int32, on reference: Date = Date(), calendar: Calendar = .current) -> Date {
    let start = calendar.startOfDay(for: reference)
    return calendar.date(byAdding: .minute, value: Int(minutes), to: start) ?? start
  }

  /// The DatePicker's time back to minutes from midnight (0–1439).
  static func minutes(of date: Date, calendar: Calendar = .current) -> Int32 {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return Int32((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
  }

  // MARK: - Preferences

  static let paceOptions: [Loci_Trip_TripPace] = [.relaxed, .moderate, .packed]

  /// web: PACE_LABELS
  static func paceLabel(_ pace: Loci_Trip_TripPace) -> String {
    switch pace {
    case .relaxed: "Relaxed"
    case .moderate: "Moderate"
    case .packed: "Packed"
    default: "—"
    }
  }

  /// Budget levels are 1–4 on the wire; money glyphs read faster than a number (web: BUDGET_LABELS).
  static func budgetLabel(_ level: Int32) -> String? {
    (1...4).contains(level) ? String(repeating: "€", count: Int(level)) : nil
  }

  /// "09:00–18:00", "—–18:00" or nil when neither end is set.
  static func dayWindow(_ constraints: Loci_Trip_TripConstraint) -> String? {
    let start = constraints.hasDayStartMinute ? minutesToHHMM(constraints.dayStartMinute) : ""
    let end = constraints.hasDayEndMinute ? minutesToHHMM(constraints.dayEndMinute) : ""
    guard !start.isEmpty || !end.isEmpty else { return nil }
    return "\(start.isEmpty ? "—" : start)–\(end.isEmpty ? "—" : end)"
  }

  /// The collapsed preferences row still states every current value (web: TripPreferences trigger).
  static func preferenceBadges(_ constraints: Loci_Trip_TripConstraint) -> [String] {
    var badges = [paceLabel(constraints.pace)]
    if constraints.hasBudgetLevel, let budget = budgetLabel(constraints.budgetLevel) { badges.append(budget) }
    if constraints.hasMobility, !constraints.mobility.isEmpty { badges.append(constraints.mobility) }
    if let window = dayWindow(constraints) { badges.append(window) }
    return badges
  }

  /// The budget after tapping `level`: a second tap on the selected level clears it.
  static func toggledBudget(current: Int32?, tapped level: Int32) -> Int32? {
    current == level ? nil : level
  }

  /// Apply a patch to the constraints the way the server wants it: optional
  /// fields are cleared rather than sent empty (mobility has `min_len: 1`).
  static func merged(_ constraints: Loci_Trip_TripConstraint, with patch: PreferencePatch) -> Loci_Trip_TripConstraint {
    var next = constraints
    switch patch {
    case .pace(let pace): next.pace = pace
    case .budget(let level):
      if let level { next.budgetLevel = level } else { next.clearBudgetLevel() }
    case .mobility(let text):
      let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
      if trimmed.isEmpty { next.clearMobility() } else { next.mobility = trimmed }
    case .dayStart(let minutes):
      if let minutes { next.dayStartMinute = minutes } else { next.clearDayStartMinute() }
    case .dayEnd(let minutes):
      if let minutes { next.dayEndMinute = minutes } else { next.clearDayEndMinute() }
    }
    return next
  }
}

/// One change to a trip's constraints from the preferences disclosure.
nonisolated enum PreferencePatch: Equatable, Sendable {
  case pace(Loci_Trip_TripPace)
  case budget(Int32?)
  case mobility(String)
  case dayStart(Int32?)
  case dayEnd(Int32?)
}
