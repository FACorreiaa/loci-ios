import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

struct RecapRulesTests {
  private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Lisbon") ?? .gmt
    return c
  }()

  private var now: Date { at(16, hour: 12) }

  private func at(_ d: Int, hour: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour)) ?? .distantPast
  }

  private func day(_ d: Int, completed: Bool = false) -> Loci_Trip_TripDay {
    var day = Loci_Trip_TripDay()
    day.date = Google_Protobuf_Timestamp(date: at(d, hour: 9))
    if completed { day.completedAt = Google_Protobuf_Timestamp(date: now) }
    return day
  }

  @Test func endsTheDayAfterTheEndDate() {
    var trip = Loci_Trip_TripDraft()
    trip.endDate = "2026-10-15"
    #expect(RecapRules.tripHasEnded(trip, now: now, calendar: calendar))
    trip.endDate = "2026-10-16"
    #expect(!RecapRules.tripHasEnded(trip, now: now, calendar: calendar))
  }

  @Test func fallsBackToTheLastDatedDay() {
    var trip = Loci_Trip_TripDraft()
    trip.days = [day(12), day(14)]
    #expect(RecapRules.tripHasEnded(trip, now: now, calendar: calendar))
    trip.days = [day(20)]
    #expect(!RecapRules.tripHasEnded(trip, now: now, calendar: calendar))
    trip.days = [Loci_Trip_TripDay()]
    #expect(!RecapRules.tripHasEnded(trip, now: now, calendar: calendar), "undated and unwalked")
  }

  @Test func endsOnceEveryDayIsWalked() {
    var trip = Loci_Trip_TripDraft()
    trip.endDate = "2026-12-01"
    trip.days = [day(20, completed: true), day(21, completed: true)]
    #expect(RecapRules.tripHasEnded(trip, now: now, calendar: calendar))
    trip.days = [day(20, completed: true), day(21)]
    #expect(!RecapRules.tripHasEnded(trip, now: now, calendar: calendar))
  }

  @Test func skipsCardsThisBuildCannotDraw() {
    var known = Loci_Recap_RecapCard()
    known.id = "intro"
    known.card = .intro(Loci_Recap_IntroCard())
    var unknown = Loci_Recap_RecapCard()
    unknown.id = "future"
    #expect(RecapRules.playable([known, unknown]).map(\.id) == ["intro"])
  }

  @Test func wording() {
    #expect(RecapRules.km(41.2) == "41 km")
    #expect(RecapRules.km(0) == "0 km")
    #expect(RecapRules.evidence(7, .saves) == "From 7 saves")
    #expect(RecapRules.evidence(1, .visits) == "From 1 visit")
    #expect(RecapRules.evidence(0, .saves).isEmpty)
    #expect(RecapRules.initials("Ana Sousa") == "AS")
    #expect(RecapRules.initials(" ") == "?")
  }

  @MainActor @Test func recapLinksOpenInTheirTabs() {
    #expect(AppRouter.tab(for: .tripRecap(tripID: "t")) == .calendar)
    #expect(AppRouter.tab(for: .sharedRecap(code: "c")) == .discover)
    #expect(AppRouter.tab(for: .yearRecap(year: 2026)) == .profile)
  }

  @Test func drawsEveryYearCard() {
    let year: [Loci_Recap_RecapCard.OneOf_Card] = [
      .yearMap(.init()), .tripsTimeline(.init()), .topCity(.init()), .tasteShift(.init()), .streak(.init()), .contributions(.init()),
      .percentile(.init()),
    ]
    let cards = year.enumerated().map { i, body in
      var c = Loci_Recap_RecapCard()
      c.id = "y\(i)"
      c.card = body
      return c
    }
    #expect(RecapRules.playable(cards).count == year.count)
    #expect(Loci_Recap_Recap.previewYear.cards.allSatisfy(RecapRules.isDrawn))
  }

  @Test func reviewYearIsLastYearOnlyInJanuary() {
    let jan = calendar.date(from: DateComponents(year: 2027, month: 1, day: 20)) ?? .distantPast
    let dec = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)) ?? .distantPast
    #expect(RecapRules.reviewYear(now: jan, calendar: calendar) == 2026)
    #expect(RecapRules.reviewYear(now: dec, calendar: calendar) == 2026)
    #expect(RecapRules.reviewYear(now: now, calendar: calendar) == 2026)
  }

  @Test func recapYearAcceptsOnlyWhatTheServerDoes() {
    #expect(AppLink.recapYear("2026") == 2026)
    #expect(AppLink.recapYear("2023") == nil)
    #expect(AppLink.recapYear("２０２６") == nil)
    #expect(AppLink.recapYear("-202") == nil)
  }
}
