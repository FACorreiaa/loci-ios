import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

struct TripPrefetchTests {
  private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC") ?? .current
    return c
  }

  private func trip(dayOn date: Date) -> Loci_Trip_TripDraft {
    var day = Loci_Trip_TripDay()
    day.date = Google_Protobuf_Timestamp(date: date)
    var t = Loci_Trip_TripDraft()
    t.days = [day]
    return t
  }

  private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) throws -> Date {
    try #require(cal.date(from: DateComponents(year: y, month: m, day: d, hour: h)))
  }

  @Test func schedulesTheEveningBeforeADayTomorrow() throws {
    let now = try at(2026, 10, 7, 12)
    let begin = TripPrefetch.nextBeginDate(trips: [trip(dayOn: try at(2026, 10, 8))], now: now, calendar: cal)
    #expect(begin == (try at(2026, 10, 7, 22)))
  }

  @Test func onTheDayItSchedulesSixHoursOut() throws {
    let now = try at(2026, 10, 8, 10)
    #expect(TripPrefetch.nextBeginDate(trips: [trip(dayOn: try at(2026, 10, 8))], now: now, calendar: cal) == now.addingTimeInterval(6 * 3600))
  }

  @Test func nothingWithinTwoDaysMeansNoSchedule() throws {
    let now = try at(2026, 10, 1)
    #expect(TripPrefetch.nextBeginDate(trips: [trip(dayOn: try at(2026, 10, 20))], now: now, calendar: cal) == nil)
    #expect(TripPrefetch.nextBeginDate(trips: [], now: now, calendar: cal) == nil)
  }
}
