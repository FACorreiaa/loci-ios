import Foundation
import Testing

@testable import loci

/// Ported from web's lib/recents/day-buckets.test.ts. The calendar is pinned to
/// one timezone so the local-midnight boundaries do not depend on the machine.
struct RecentsBucketsTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Lisbon") ?? .gmt
    return calendar
  }()

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
  }

  private func at(_ date: Date?, id: String? = nil) -> ActivityEntry {
    ActivityEntry(
      id: id ?? date.map { "\($0.timeIntervalSince1970)" } ?? "undated",
      kind: .prompt,
      detail: "general",
      label: "something",
      cityName: "Porto",
      refId: "s",
      occurredAt: date
    )
  }

  // The boundary is calendar days in the viewer's timezone, not elapsed hours.
  @Test func lastNightIsYesterdayJustAfterMidnight() {
    let now = date(2026, 9, 18, 0, 30)
    let groups = DayBuckets.bucket([at(date(2026, 9, 17, 23, 50))], now: now, calendar: calendar)
    #expect(groups.map(\.key) == [.yesterday])
  }

  @Test func separatesTodayYesterdayThisWeekAndEarlier() {
    let now = date(2026, 9, 18, 12)
    let groups = DayBuckets.bucket(
      [at(now.addingTimeInterval(-2 * 3600)), at(date(2026, 9, 17, 9)), at(date(2026, 9, 14, 9)), at(date(2026, 7, 1, 9))],
      now: now,
      calendar: calendar
    )
    #expect(groups.map(\.key) == [.today, .yesterday, .week, .earlier])
    #expect(groups.allSatisfy { $0.entries.count == 1 })
    #expect(groups.map(\.label) == ["Today", "Yesterday", "This week", "Earlier"])
  }

  @Test func dropsGroupsThatWouldBeEmpty() {
    let now = date(2026, 9, 18, 12)
    let groups = DayBuckets.bucket([at(now.addingTimeInterval(-3600))], now: now, calendar: calendar)
    #expect(groups.map(\.key) == [.today])
  }

  @Test func keepsTheGivenOrderInsideAGroup() {
    let now = date(2026, 9, 18, 12)
    let newer = at(now.addingTimeInterval(-3600), id: "newer")
    let older = at(now.addingTimeInterval(-5 * 3600), id: "older")
    let groups = DayBuckets.bucket([newer, older], now: now, calendar: calendar)
    #expect(groups.first?.entries.map(\.id) == ["newer", "older"])
  }

  /// Web's "unparseable timestamp" case: no time at all files under Earlier.
  @Test func undatedEntryGoesUnderEarlier() {
    let groups = DayBuckets.bucket([at(nil)], now: date(2026, 9, 18, 12), calendar: calendar)
    #expect(groups.map(\.key) == [.earlier])
  }

  @Test func sixDaysIsThisWeekAndSevenIsEarlier() {
    let now = date(2026, 9, 18, 12)
    let groups = DayBuckets.bucket([at(date(2026, 9, 12, 23)), at(date(2026, 9, 11, 23))], now: now, calendar: calendar)
    #expect(groups.map(\.key) == [.week, .earlier])
  }

  @Test func relativeTimeShortensWithDistance() {
    let now = date(2026, 9, 18, 12)
    #expect(DayBuckets.relativeTime(now.addingTimeInterval(-30), now: now, calendar: calendar) == "just now")
    #expect(DayBuckets.relativeTime(now.addingTimeInterval(-5 * 60), now: now, calendar: calendar) == "5m ago")
    #expect(DayBuckets.relativeTime(now.addingTimeInterval(-3 * 3600), now: now, calendar: calendar) == "3h ago")
    #expect(DayBuckets.relativeTime(date(2026, 9, 17, 9), now: now, calendar: calendar) == "yesterday")
    #expect(DayBuckets.relativeTime(date(2026, 9, 15, 9), now: now, calendar: calendar) == "3d ago")
  }

  @Test func relativeTimeFallsBackToADateAfterAWeek() {
    let now = date(2026, 9, 18, 12)
    let text = DayBuckets.relativeTime(date(2026, 3, 12, 9), now: now, calendar: calendar)
    #expect(text.contains("12"))
    #expect(!text.contains("ago"))
  }

  @Test func relativeTimeIsEmptyWithoutATimestamp() {
    #expect(DayBuckets.relativeTime(nil, now: Date(), calendar: calendar).isEmpty)
  }

  @Test func aTimestampInTheFutureReadsJustNow() {
    let now = date(2026, 9, 18, 12)
    #expect(DayBuckets.relativeTime(now.addingTimeInterval(120), now: now, calendar: calendar) == "just now")
  }
}
