import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

@MainActor struct CalendarMathTests {
  @Test func dateKeyUsesLocalDay() throws {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let date = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 8)))
    #expect(CalendarMath.dateKey(date, calendar: cal) == "2026-10-08")
  }

  @Test func october2026StartsOnMondayGrid() throws {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let cells = CalendarMath.monthCells(year: 2026, month: 10, calendar: cal)
    #expect(cells.first?.dateKey == "2026-09-28")
    #expect(cells.first?.inMonth == false)
    #expect(cells.contains(where: { $0.dateKey == "2026-10-01" && $0.inMonth }))
    #expect(cells.count.isMultiple(of: 7))
    #expect(cells.last?.dateKey == "2026-11-01")
  }
}

/// Pinning a trip to dates is the one SaveTrip iOS sends for a trip that
/// already exists; SaveTrip replaces everything, so it must send legs back
/// with the ids the server gave them.
@MainActor struct CalendarPinTests {
  private func leg(_ id: String, _ from: String, _ to: String, afterDay: Int32) -> Loci_Trip_TripLeg {
    var leg = Loci_Trip_TripLeg()
    leg.id = id
    leg.fromName = from
    leg.toName = to
    leg.afterDay = afterDay
    return leg
  }

  @Test func pinningSendsLegsBackWithTheirIds() throws {
    var trip = Loci_Trip_TripDraft()
    trip.id = "t1"
    trip.version = 4
    for number in Int32(1)...3 {
      var day = Loci_Trip_TripDay()
      day.dayNumber = number
      trip.days.append(day)
    }
    trip.legs = [leg("leg-a", "Lisbon", "Porto", afterDay: 1), leg("leg-b", "Porto", "Braga", afterDay: 2)]
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let start = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 8)))

    let request = CalendarPin.saveRequest(trip, start: start, calendar: cal)

    #expect(request.baseVersion == 4)
    #expect(request.trip.id == "t1")
    #expect(request.trip.legs.map(\.id) == ["leg-a", "leg-b"])
    #expect(request.trip.legs == trip.legs)
    #expect(request.trip.days.map { CalendarMath.dateKey($0.date.date, calendar: cal) } == ["2026-10-08", "2026-10-09", "2026-10-10"])
  }
}
