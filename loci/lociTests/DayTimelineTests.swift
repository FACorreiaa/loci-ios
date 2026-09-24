import CoreLocation
import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

struct DayTimelineTests {
  private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC") ?? .current
    return c
  }

  private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in cal: Calendar) throws -> Date {
    try #require(cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)))
  }

  private func stop(_ name: String, start: Int? = nil, minutes: Int? = nil, lat: Double? = nil, lon: Double? = nil) -> Loci_Trip_TripStop {
    var s = Loci_Trip_TripStop()
    s.id = name
    s.name = name
    if let start { s.startMinute = Int32(start) }
    if let minutes { s.durationMinutes = Int32(minutes) }
    if let lat, let lon {
      s.poi.latitude = lat
      s.poi.longitude = lon
    }
    return s
  }

  private func day(_ date: Date?, stops: [Loci_Trip_TripStop], travel: Bool = false) -> Loci_Trip_TripDay {
    var d = Loci_Trip_TripDay()
    d.id = UUID().uuidString
    if let date { d.date = Google_Protobuf_Timestamp(date: date) }
    d.stops = stops
    d.travelDay = travel
    return d
  }

  @Test func defaultsStartAtNineWithNinetyMinuteSlotsAndBuffers() throws {
    let cal = utc
    let d = day(try date(2026, 10, 8, in: cal), stops: [stop("A"), stop("B")])
    let slots = DayTimeline.slots(day: d, legs: [], calendar: cal)
    #expect(slots.map(\.index) == [0, 1])
    #expect(slots[0].start == (try date(2026, 10, 8, 9, 0, in: cal)))
    #expect(slots[0].end == (try date(2026, 10, 8, 10, 30, in: cal)))
    #expect(slots[1].start == (try date(2026, 10, 8, 10, 45, in: cal)))
  }

  @Test func explicitStartAndDurationWinAndAreClamped() throws {
    let cal = utc
    let d = day(try date(2026, 10, 8, in: cal), stops: [stop("A", start: 14 * 60, minutes: 10), stop("B", minutes: 600)])
    let slots = DayTimeline.slots(day: d, legs: [], calendar: cal)
    #expect(slots[0].start == (try date(2026, 10, 8, 14, 0, in: cal)))
    #expect(slots[0].end == (try date(2026, 10, 8, 14, 30, in: cal)))
    #expect(slots[1].end.timeIntervalSince(slots[1].start) == 240 * 60)
  }

  @Test func dayStartMinuteMovesTheFirstStop() throws {
    let cal = utc
    let d = day(try date(2026, 10, 8, in: cal), stops: [stop("A")])
    let slots = DayTimeline.slots(day: d, legs: [], dayStartMinute: 10 * 60 + 30, calendar: cal)
    #expect(slots[0].start == (try date(2026, 10, 8, 10, 30, in: cal)))
  }

  @Test func distanceComesFromTheLegElseTheStraightLine() throws {
    let cal = utc
    var leg = Loci_Trip_TripLeg()
    leg.fromName = "A"
    leg.toName = "B"
    leg.distanceKm = 1.5
    let d = day(try date(2026, 10, 8, in: cal), stops: [
      stop("A", lat: 41.9028, lon: 12.4964), stop("B", lat: 41.8902, lon: 12.4922), stop("C", lat: 41.8986, lon: 12.4769),
    ])
    let slots = DayTimeline.slots(day: d, legs: [leg], calendar: cal)
    #expect(slots[0].distanceToNextMeters == 1500)
    let straight = try #require(slots[1].distanceToNextMeters)
    #expect(straight > 1400 && straight < 1700)
    #expect(slots[2].distanceToNextMeters == nil)
  }

  @Test func todayMatchesTheCalendarDayWestOfUTC() throws {
    var losAngeles = Calendar(identifier: .gregorian)
    losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let midnightUTC = try date(2026, 10, 8, in: utc)  // 17:00 the day before in Los Angeles
    var trip = Loci_Trip_TripDraft()
    trip.days = [day(midnightUTC, stops: [stop("A")])]
    let nowLA = try #require(losAngeles.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 9)))
    #expect(DayTimeline.today(in: trip, now: nowLA, calendar: losAngeles)?.id == trip.days[0].id)
  }

  @Test func todaySkipsTravelDaysAndTakesTheFirstOfTwo() throws {
    let cal = utc
    let d = try date(2026, 10, 8, in: cal)
    var trip = Loci_Trip_TripDraft()
    let travel = day(d, stops: [], travel: true)
    let first = day(d, stops: [stop("A")])
    let second = day(d, stops: [stop("B")])
    trip.days = [travel, first, second]
    #expect(DayTimeline.today(in: trip, now: try date(2026, 10, 8, 12, in: cal), calendar: cal)?.id == first.id)
    #expect(DayTimeline.today(in: trip, now: try date(2026, 10, 9, 12, in: cal), calendar: cal) == nil)
  }

  @Test func currentAndNextFollowTheClock() throws {
    let cal = utc
    let d = day(try date(2026, 10, 8, in: cal), stops: [stop("A"), stop("B")])
    let slots = DayTimeline.slots(day: d, legs: [], calendar: cal)
    #expect(DayTimeline.current(slots, at: try date(2026, 10, 8, 8, in: cal)) == nil)
    #expect(DayTimeline.current(slots, at: try date(2026, 10, 8, 9, 30, in: cal))?.index == 0)
    #expect(DayTimeline.current(slots, at: try date(2026, 10, 8, 10, 40, in: cal))?.index == 0)
    #expect(DayTimeline.current(slots, at: try date(2026, 10, 8, 13, in: cal))?.index == 1)
    #expect(DayTimeline.next(slots, after: slots[0])?.index == 1)
    #expect(DayTimeline.next(slots, after: slots[1]) == nil)
  }

  /// The app's own Calendar pin used to store local midnight; east of UTC that
  /// is the previous evening in UTC. The date must still read as that day.
  @Test func todayMatchesTheCalendarDayEastOfUTCForALocalMidnightDate() throws {
    var lisbonSummer = Calendar(identifier: .gregorian)
    lisbonSummer.timeZone = try #require(TimeZone(identifier: "Europe/Athens"))  // UTC+3 in summer
    let localMidnight = try #require(lisbonSummer.date(from: DateComponents(year: 2026, month: 7, day: 8)))  // 21:00Z on the 7th
    var trip = Loci_Trip_TripDraft()
    trip.days = [day(localMidnight, stops: [stop("A")])]
    let now = try #require(lisbonSummer.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 10)))
    #expect(DayTimeline.today(in: trip, now: now, calendar: lisbonSummer)?.id == trip.days[0].id)
    let slots = DayTimeline.slots(day: trip.days[0], legs: [], calendar: lisbonSummer)
    #expect(slots[0].start == lisbonSummer.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 9)))
  }

  /// What the app writes when it pins a trip: midnight UTC of the chosen day.
  @Test func pinnedDateIsMidnightUTCOfTheChosenDay() throws {
    var athens = Calendar(identifier: .gregorian)
    athens.timeZone = try #require(TimeZone(identifier: "Europe/Athens"))
    let chosen = try #require(athens.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 15)))
    let pinned = DayTimeline.utcMidnight(ofDayContaining: chosen, calendar: athens)
    #expect(pinned == (try date(2026, 7, 8, in: utc)))
  }
}
