import Foundation

/// A day of the opening-hours week, Monday first (web: DAYS in `lib/place-facts/opening-hours.ts`).
nonisolated enum HoursDay: String, CaseIterable, Identifiable, Sendable {
  case mon, tue, wed, thu, fri, sat, sun

  var id: String { rawValue }

  var label: String {
    switch self {
    case .mon: "Monday"
    case .tue: "Tuesday"
    case .wed: "Wednesday"
    case .thu: "Thursday"
    case .fri: "Friday"
    case .sat: "Saturday"
    case .sun: "Sunday"
    }
  }
}

/// "HH:MM" to "HH:MM"; start 00:00–23:59, end 00:01–24:00.
nonisolated struct HoursInterval: Hashable, Sendable {
  var start: String
  var end: String
}

/// A day is either closed, or open for one or more intervals.
nonisolated enum DayHours: Hashable, Sendable {
  case closed
  case open([HoursInterval])

  var isClosed: Bool { self == .closed }
}

/// Opening hours as a week the scout edits, and the one canonical string it
/// is sent as. Ported from web's `lib/place-facts/opening-hours.ts`.
///
/// Two scouts' reports corroborate only when they are byte-identical, so the
/// encoding has exactly one form per week: all seven days, Monday first,
/// intervals sorted and merged, identical consecutive days collapsed into a
/// range. Times are 24-hour wall-clock at the place; a close at midnight is
/// `24:00`, so an interval always reads forwards.
nonisolated struct OpeningHours: Hashable, Sendable {
  private var days: [HoursDay: DayHours]

  init(_ days: [HoursDay: DayHours]) { self.days = days }

  subscript(day: HoursDay) -> DayHours {
    get { days[day] ?? .closed }
    set { days[day] = newValue }
  }

  static let weekdayInterval = HoursInterval(start: "09:00", end: "17:00")

  /// Weekdays 09:00–17:00, weekend closed: quicker to correct than seven empty days,
  /// and a half-filled week has no canonical form.
  static var `default`: OpeningHours {
    var week: [HoursDay: DayHours] = [:]
    for day in HoursDay.allCases { week[day] = day == .sat || day == .sun ? .closed : .open([weekdayInterval]) }
    return OpeningHours(week)
  }

  /// True when every open day has hours and every interval is a well-formed, forward-running span.
  var isValid: Bool {
    HoursDay.allCases.allSatisfy { day in
      switch self[day] {
      case .closed: return true
      case .open(let intervals):
        guard !intervals.isEmpty else { return false }
        return intervals.allSatisfy { interval in
          guard Self.isTime(interval.start), Self.isTime(interval.end), let start = Self.minutes(interval.start), let end = Self.minutes(interval.end)
          else { return false }
          return start < end
        }
      }
    }
  }

  /// The canonical string, e.g. `mon-fri 09:00-17:00; sat 10:00-14:00; sun closed`.
  var encoded: String {
    let days = HoursDay.allCases
    var groups: [String] = []
    var runStart = 0
    for index in 0...days.count {
      let current = index < days.count ? Self.dayString(self[days[index]]) : nil
      let running = Self.dayString(self[days[runStart]])
      if current == running { continue }
      let lastOfRun = index - 1
      let daySpec = runStart == lastOfRun ? days[runStart].rawValue : "\(days[runStart].rawValue)-\(days[lastOfRun].rawValue)"
      groups.append("\(daySpec) \(running)")
      runStart = index
    }
    return groups.joined(separator: "; ")
  }

  /// Reads a canonical string back into a week. Nil for anything it does not
  /// recognise rather than a guess: a guess becomes a claim nobody can corroborate.
  static func parse(_ value: String) -> OpeningHours? {
    var week: [HoursDay: DayHours] = [:]
    for rawGroup in value.split(separator: ";", omittingEmptySubsequences: false) {
      let group = rawGroup.trimmingCharacters(in: .whitespaces)
      if group.isEmpty { continue }
      guard let separator = group.firstIndex(of: " ") else { return nil }
      let daySpec = group[..<separator]
      let intervalSpec = group[group.index(after: separator)...].trimmingCharacters(in: .whitespaces)

      let ends = daySpec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
      guard let from = ends.first.flatMap(HoursDay.init(rawValue:)), let fromIndex = HoursDay.allCases.firstIndex(of: from) else { return nil }
      var toIndex = fromIndex
      if ends.count > 1 {
        guard let to = HoursDay(rawValue: ends[1]), let index = HoursDay.allCases.firstIndex(of: to) else { return nil }
        toIndex = index
      }
      guard toIndex >= fromIndex else { return nil }

      let hours: DayHours
      if intervalSpec == "closed" {
        hours = .closed
      } else {
        var intervals: [HoursInterval] = []
        for part in intervalSpec.split(separator: ",", omittingEmptySubsequences: false) {
          let edges = part.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false).map(String.init)
          guard edges.count >= 2, isTime(edges[0]), isTime(edges[1]) else { return nil }
          intervals.append(HoursInterval(start: edges[0], end: edges[1]))
        }
        hours = .open(intervals)
      }
      for index in fromIndex...toIndex { week[HoursDay.allCases[index]] = hours }
    }
    guard HoursDay.allCases.allSatisfy({ week[$0] != nil }) else { return nil }
    return OpeningHours(week)
  }

  /// web: OpeningHoursPicker.setTime. Changes one edge of the day's first
  /// interval (the editor shows one span a day); a closed day is left alone.
  mutating func setTime(_ day: HoursDay, start: Bool, to time: String) {
    guard case .open(let intervals) = self[day], Self.isTime(time) else { return }
    var first = intervals.first ?? Self.weekdayInterval
    // A clock cannot show 24:00, so a close picked at midnight means the end of
    // the day, which is the only forward-running reading of it.
    if start { first.start = time } else { first.end = time == "00:00" ? "24:00" : time }
    self[day] = .open([first] + intervals.dropFirst())
  }

  /// Why a day cannot be sent, or nil when it can. The editor shows it under
  /// the row so a disabled Submit is never a mystery.
  func problem(_ day: HoursDay) -> String? {
    guard case .open(let intervals) = self[day] else { return nil }
    guard let first = intervals.first else { return "Set hours or mark it closed." }
    guard let start = Self.minutes(first.start), let end = Self.minutes(first.end) else { return "Set hours or mark it closed." }
    return start < end ? nil : "Closes before it opens. Past-midnight hours aren't supported yet."
  }

  /// web: the "Closed" / "Set hours" button. Reopening starts at 09:00–17:00.
  mutating func toggleClosed(_ day: HoursDay) { self[day] = self[day].isClosed ? .open([Self.weekdayInterval]) : .closed }

  // MARK: - Clock

  /// "HH:MM" as a time on a fixed GMT day, for a `DatePicker` shown in GMT, so
  /// neither the device's zone nor daylight saving can move it.
  static func clockDate(_ time: String) -> Date { Date(timeIntervalSinceReferenceDate: TimeInterval((minutes(time) ?? 0) * 60)) }

  /// A picked time back as "HH:MM", read in GMT.
  static func clockString(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
  }

  // MARK: - Helpers

  /// `HH:MM` 00:00–23:59, or exactly `24:00` (web's TIME pattern).
  static func isTime(_ value: String) -> Bool { value.wholeMatch(of: /(?:(?:[01]\d|2[0-3]):[0-5]\d|24:00)/) != nil }

  static func minutes(_ time: String) -> Int? {
    let parts = time.split(separator: ":")
    guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
    return hours * 60 + minutes
  }

  /// Sorts intervals and merges any that overlap or touch.
  static func merge(_ intervals: [HoursInterval]) -> [HoursInterval] {
    let sorted = intervals.sorted { (minutes($0.start) ?? 0) < (minutes($1.start) ?? 0) }
    var merged: [HoursInterval] = []
    for interval in sorted {
      if let previous = merged.last, (minutes(interval.start) ?? 0) <= (minutes(previous.end) ?? 0) {
        if (minutes(interval.end) ?? 0) > (minutes(previous.end) ?? 0) { merged[merged.count - 1].end = interval.end }
        continue
      }
      merged.append(interval)
    }
    return merged
  }

  private static func dayString(_ hours: DayHours) -> String {
    guard case .open(let intervals) = hours else { return "closed" }
    let merged = merge(intervals)
    if merged.isEmpty { return "closed" }
    return merged.map { "\($0.start)-\($0.end)" }.joined(separator: ",")
  }
}
