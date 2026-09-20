import Foundation
import Testing

@testable import loci

struct CalendarMathTests {
  @Test func dateKeyUsesLocalDay() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 8))!
    #expect(CalendarMath.dateKey(date, calendar: cal) == "2026-10-08")
  }

  @Test func october2026StartsOnMondayGrid() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let cells = CalendarMath.monthCells(year: 2026, month: 10, calendar: cal)
    #expect(cells.first?.dateKey == "2026-09-28")
    #expect(cells.first?.inMonth == false)
    #expect(cells.contains(where: { $0.dateKey == "2026-10-01" && $0.inMonth }))
    #expect(cells.count.isMultiple(of: 7))
    #expect(cells.last?.dateKey == "2026-11-01")
  }
}
