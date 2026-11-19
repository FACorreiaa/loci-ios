import Foundation
import LociConnectProto
import SwiftProtobuf

/// The words a stop's map check is shown with. Mirrors the web
/// (`src/lib/stop-check.ts`) so both say the same thing.
///
/// Two facts are kept apart. `mark` says the place was found on a real map.
/// `detail` says what the map's listed hours mean for the visit as planned.
/// "Checked" only ever means the first: a place with no hours listed says so,
/// and never reads as confirmed open.
nonisolated struct StopCheckLine: Equatable {
  enum Tone: Equatable {
    /// Found, and nothing in its hours argues with the plan.
    case ok
    /// Found, and the plan as timed meets a shut door.
    case attention
    /// Not found on the map. Not the same as "does not exist".
    case unknown
  }

  let tone: Tone
  let mark: String
  /// What the hours say, or "" when there is nothing to add.
  let detail: String
  /// A longer sentence for VoiceOver.
  let explain: String

  /// Nil for a stop the server has not looked up: show no stamp then.
  /// `dayDate` is the day's date, used only to name the weekday a place is
  /// shut on.
  init?(_ check: Loci_Trip_StopCheck, dayDate: Date? = nil) {
    switch check.status {
    case .notFound:
      tone = .unknown
      mark = "Couldn't check"
      detail = ""
      explain = "We could not find this place on the map. It may still be real: look it up before you go."
      return
    case .checked:
      break
    case .unspecified, .UNRECOGNIZED:
      return nil
    }

    let opens = check.hasOpensMinute ? Int(check.opensMinute) : nil
    let closes = check.hasClosesMinute ? Int(check.closesMinute) : nil
    var detail: String
    var explain: String
    var attention = false

    switch check.hours {
    case .unspecified:
      detail = "hours not listed"
      explain = "Found on the map. The map lists no opening hours for it."
    case .listed:
      detail = "set a date to check hours"
      explain = "Found on the map. Give this day a date and we will hold its hours to your plan."
    case .openThatDay:
      detail = "open that day"
      explain = "Found on the map, and open on this day. Give the stop a time to check it."
    case .open:
      if opens == 0, closes == 1440 {
        detail = "always open"
      } else if let closes {
        detail = "open until \(Self.clock(closes))"
      } else {
        detail = "open"
      }
      explain = "Found on the map, and open for the whole of your visit."
    case .shutThatDay:
      attention = true
      detail = dayDate.map { "shut \(Self.weekday($0))" } ?? "shut that day"
      explain = "Found on the map, but shut all day on the day you planned it."
    case .opensLater:
      attention = true
      detail = opens.map { "opens \(Self.clock($0))" } ?? "opens later"
      explain = "Found on the map, but not yet open at the time you planned."
    case .closesEarly:
      attention = true
      detail = closes.map { "shuts \(Self.clock($0))" } ?? "shuts early"
      explain = "Found on the map, but it shuts before your visit ends."
    case .shutByThen:
      attention = true
      detail = closes.map { "shut from \(Self.clock($0))" } ?? "shut by then"
      explain = "Found on the map, but already shut for the day by the time you planned."
    case .unreadable, .UNRECOGNIZED:
      // An hours value this build does not know is treated like one the
      // server could not read: it is the one answer that claims nothing.
      detail = "hours vary"
      explain = "Found on the map. Its hours change by season or need arranging, so check them before you go."
    }

    if !check.holidayName.isEmpty {
      if check.holidayHoursUnknown {
        detail += " · \(check.holidayName), hours may differ"
        explain += " This day is a public holiday (\(check.holidayName)) and the map lists no holiday hours."
      } else {
        detail += " · \(check.holidayName)"
      }
    }

    tone = attention ? .attention : .ok
    mark = "Checked"
    self.detail = detail
    self.explain = explain
  }

  /// Minutes from midnight as a clock time; a close past midnight wraps.
  static func clock(_ minute: Int) -> String {
    let m = ((minute % 1440) + 1440) % 1440
    if m == 0 { return "midnight" }
    return String(format: "%02d:%02d", m / 60, m % 60)
  }

  /// The short weekday of a trip day, read in UTC as the trip stores it.
  static func weekday(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    return symbols[(calendar.component(.weekday, from: date) - 1) % 7]
  }
}

/// A day's checks summed: "5 of 5 checked", and how many need a look.
nonisolated struct DayCheckTally: Equatable {
  /// Stops whose place was found on the map.
  var checked = 0
  /// Stops the map has answered for at all.
  var total = 0
  var needAttention = 0

  init(stops: [Loci_Trip_TripStop], dayDate: Date? = nil) {
    for stop in stops where stop.hasCheck {
      guard let line = StopCheckLine(stop.check, dayDate: dayDate) else { continue }
      total += 1
      if line.tone != .unknown { checked += 1 }
      if line.tone == .attention { needAttention += 1 }
    }
  }

  /// Nil when nothing on the day was checked: the header then says nothing.
  var label: String? {
    guard total > 0 else { return nil }
    let base = "\(checked) of \(total) checked"
    guard needAttention > 0 else { return base }
    return "\(base) · \(needAttention) need\(needAttention == 1 ? "s" : "") a look"
  }
}

nonisolated extension Loci_Trip_TripDay {
  /// The day's calendar date, when the trip has dates.
  var checkDate: Date? { hasDate ? date.date : nil }
}
