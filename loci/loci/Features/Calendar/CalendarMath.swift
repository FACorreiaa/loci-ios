import Foundation

public struct CalendarTripBlock: Equatable, Sendable, Identifiable {
  public var id: String { "\(tripId)-\(dayNumber)-\(dateKey)" }
  public let tripId: String
  public let title: String
  public let cityName: String
  public let dayNumber: Int32
  public let dateKey: String
}

public struct MonthCell: Equatable, Sendable {
  public let dateKey: String
  public let inMonth: Bool
  public let day: Int
}

public enum CalendarMath {
  public static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  public static func parseDateKey(_ key: String, calendar: Calendar = .current) -> Date? {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }

  public static func monthCells(year: Int, month: Int, calendar: Calendar = .current) -> [MonthCell] {
    var cal = calendar
    cal.firstWeekday = 2
    guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1)),
      let range = cal.range(of: .day, in: .month, for: first)
    else { return [] }

    let weekday = cal.component(.weekday, from: first)
    let mondayIndex = (weekday + 5) % 7
    var cells: [MonthCell] = []

    if mondayIndex > 0, let start = cal.date(byAdding: .day, value: -mondayIndex, to: first) {
      for offset in 0..<mondayIndex {
        if let d = cal.date(byAdding: .day, value: offset, to: start) {
          cells.append(
            MonthCell(
              dateKey: dateKey(d, calendar: cal),
              inMonth: false,
              day: cal.component(.day, from: d)
            )
          )
        }
      }
    }

    for day in range {
      if let d = cal.date(from: DateComponents(year: year, month: month, day: day)) {
        cells.append(MonthCell(dateKey: dateKey(d, calendar: cal), inMonth: true, day: day))
      }
    }

    let remainder = cells.count % 7
    if remainder != 0, let last = cal.date(from: DateComponents(year: year, month: month, day: range.count)) {
      for offset in 1...(7 - remainder) {
        if let d = cal.date(byAdding: .day, value: offset, to: last) {
          cells.append(
            MonthCell(
              dateKey: dateKey(d, calendar: cal),
              inMonth: false,
              day: cal.component(.day, from: d)
            )
          )
        }
      }
    }
    return cells
  }
}
