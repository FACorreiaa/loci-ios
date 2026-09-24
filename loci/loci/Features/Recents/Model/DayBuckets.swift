import Foundation

/// Today / Yesterday / This week / Earlier (web: lib/recents/day-buckets.ts).
nonisolated struct ActivityDayGroup: Identifiable, Equatable, Sendable {
  enum Key: String, Sendable { case today, yesterday, week, earlier }

  let key: Key
  var entries: [ActivityEntry]

  var id: Key { key }

  var label: String {
    switch key {
    case .today: "Today"
    case .yesterday: "Yesterday"
    case .week: "This week"
    case .earlier: "Earlier"
    }
  }
}

nonisolated enum DayBuckets {
  /// Group entries by calendar day in the viewer's timezone, not by elapsed
  /// hours: at 00:30 an entry from 23:50 is yesterday. Entries arrive newest
  /// first and keep that order inside a group; empty groups are dropped. `now`
  /// is passed in so the result is a pure function of its inputs.
  static func bucket(_ entries: [ActivityEntry], now: Date, calendar: Calendar = .current) -> [ActivityDayGroup] {
    var groups: [ActivityDayGroup.Key: [ActivityEntry]] = [:]
    for entry in entries {
      let key: ActivityDayGroup.Key
      if let at = entry.occurredAt {
        let days = daysBetween(at, now, calendar: calendar)
        key = days <= 0 ? .today : days == 1 ? .yesterday : days < 7 ? .week : .earlier
      } else {
        key = .earlier
      }
      groups[key, default: []].append(entry)
    }
    return [ActivityDayGroup.Key.today, .yesterday, .week, .earlier].compactMap { key in
      groups[key].map { ActivityDayGroup(key: key, entries: $0) }
    }
  }

  /// "just now", "5m ago", "3h ago", "yesterday", "3d ago", then "12 Mar".
  /// Empty when there is no timestamp.
  static func relativeTime(_ date: Date?, now: Date, calendar: Calendar = .current) -> String {
    guard let date else { return "" }
    let minutes = Int((now.timeIntervalSince(date) / 60).rounded(.down))
    if minutes < 1 { return "just now" }
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = daysBetween(date, now, calendar: calendar)
    if days == 1 { return "yesterday" }
    if days < 7 { return "\(days)d ago" }
    var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
    style.timeZone = calendar.timeZone
    return date.formatted(style)
  }

  /// Whole calendar days from `date` to `now`, counted between local midnights.
  static func daysBetween(_ date: Date, _ now: Date, calendar: Calendar) -> Int {
    calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
  }
}
