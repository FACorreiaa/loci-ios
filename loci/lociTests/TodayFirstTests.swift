import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

struct TodayFirstTests {
  private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC") ?? .current
    return c
  }

  private func at(_ d: Int, _ h: Int = 12, _ m: Int = 0) throws -> Date {
    try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m)))
  }

  private func stop(_ name: String, order: Int32, start: Int32? = nil) -> Loci_Trip_TripStop {
    var s = Loci_Trip_TripStop()
    s.id = name
    s.name = name
    s.orderIndex = order
    if let start { s.startMinute = start }
    return s
  }

  private func trip(_ id: String, days: [Int], stops: [[Loci_Trip_TripStop]] = []) throws -> Loci_Trip_TripDraft {
    var t = Loci_Trip_TripDraft()
    t.id = id
    t.cityName = "Lisbon"
    for (i, d) in days.enumerated() {
      var day = Loci_Trip_TripDay()
      day.id = "\(id)-\(i)"
      day.dayNumber = Int32(i + 1)
      day.date = Google_Protobuf_Timestamp(date: try at(d, 0))
      day.stops = i < stops.count ? stops[i] : []
      t.days.append(day)
    }
    return t
  }

  @Test func pickNilOutsideTrip() throws {
    let t = try trip("a", days: [21, 22])
    #expect(TodayFirst.pick(trips: [t], now: try at(20), calendar: utc) == nil)
  }

  @Test func pickTodayDay() throws {
    let t = try trip("a", days: [19, 20, 21])
    let today = try #require(TodayFirst.pick(trips: [t], now: try at(20), calendar: utc))
    #expect(today.day.dayNumber == 2)
    #expect(today.trip.id == "a")
  }

  @Test func pickLatestStartWhenOverlapping() throws {
    let long = try trip("long", days: [15, 20, 25])
    let short = try trip("short", days: [20, 21])
    #expect(TodayFirst.pick(trips: [long, short], now: try at(20), calendar: utc)?.trip.id == "short")
  }

  @Test func nextStopIsTheFirstStillAhead() throws {
    let stops = [[stop("Breakfast", order: 0, start: 540), stop("Museum", order: 1, start: 840), stop("Dinner", order: 2, start: 1200)]]
    let today = try #require(TodayFirst.pick(trips: [try trip("a", days: [20], stops: stops)], now: try at(20, 13, 30), calendar: utc))
    #expect(today.next?.name == "Museum")
  }

  @Test func nextStopFallsBackToTheFirst() throws {
    let stops = [[stop("Breakfast", order: 0, start: 540), stop("Lunch", order: 1, start: 720)]]
    let today = try #require(TodayFirst.pick(trips: [try trip("a", days: [20], stops: stops)], now: try at(20, 18), calendar: utc))
    #expect(today.next?.name == "Breakfast")
  }

  /// The trip brief's push carries the trip's web address; a tap opens it.
  @Test func briefPushOpensTheTrip() {
    let brief: [AnyHashable: Any] = ["url": "https://lociai.fyi/trips/t1", "origin": "trip_brief", "category": "loci_brief"]
    #expect(PushRoute.tap(userInfo: brief) == .openLink(.trip(id: "t1")))
  }

  /// A brief that saw a closed stop opens the trip on swapping it.
  @Test func briefPushWithAClosedStopOpensTheSwap() {
    let brief: [AnyHashable: Any] = ["url": "https://lociai.fyi/trips/t1?swap=s9", "origin": "trip_brief", "category": "loci_brief"]
    #expect(PushRoute.tap(userInfo: brief) == .openLink(.trip(id: "t1", swapStopID: "s9")))
  }
}
