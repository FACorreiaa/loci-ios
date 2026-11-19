import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

struct StopCheckLineTests {
  /// 2026-04-14 is a Tuesday.
  private let tuesday = Date(timeIntervalSince1970: 1_776_124_800)

  private func check(
    _ hours: Loci_Trip_StopHoursState = .unspecified,
    status: Loci_Trip_StopCheckStatus = .checked,
    opens: Int32? = nil,
    closes: Int32? = nil,
    holiday: String = "",
    holidayUnknown: Bool = false
  ) -> Loci_Trip_StopCheck {
    var c = Loci_Trip_StopCheck()
    c.status = status
    c.hours = hours
    if let opens { c.opensMinute = opens }
    if let closes { c.closesMinute = closes }
    c.holidayName = holiday
    c.holidayHoursUnknown = holidayUnknown
    return c
  }

  private func stop(_ check: Loci_Trip_StopCheck?) -> Loci_Trip_TripStop {
    var s = Loci_Trip_TripStop()
    if let check { s.check = check }
    return s
  }

  @Test func aStopNotLookedUpHasNoStamp() {
    #expect(StopCheckLine(check(status: .unspecified)) == nil)
  }

  @Test func aPlaceNotFoundIsNeverCalledFake() throws {
    let line = try #require(StopCheckLine(check(status: .notFound)))
    #expect(line.tone == .unknown)
    #expect(line.mark == "Couldn't check")
    #expect(line.detail.isEmpty)
    #expect(line.explain.contains("may still be real"))
  }

  @Test func checkedDoesNotClaimHoursNobodyListed() throws {
    let line = try #require(StopCheckLine(check()))
    #expect(line.tone == .ok)
    #expect(line.mark == "Checked")
    #expect(line.detail == "hours not listed")
  }

  @Test(arguments: [
    (Loci_Trip_StopHoursState.unreadable, nil as Int32?, nil as Int32?, "hours vary", false),
    (.listed, nil, nil, "set a date to check hours", false),
    (.openThatDay, nil, nil, "open that day", false),
    (.open, 600, 1080, "open until 18:00", false),
    (.open, 0, 1440, "always open", false),
    (.open, 600, 1440, "open until midnight", false),
    (.open, 1080, 1560, "open until 02:00", false),
    (.shutThatDay, nil, nil, "shut Tue", true),
    (.opensLater, 600, nil, "opens 10:00", true),
    (.closesEarly, nil, 1020, "shuts 17:00", true),
    (.shutByThen, nil, 1020, "shut from 17:00", true),
  ])
  func hoursRead(hours: Loci_Trip_StopHoursState, opens: Int32?, closes: Int32?, detail: String, attention: Bool) throws {
    let line = try #require(StopCheckLine(check(hours, opens: opens, closes: closes), dayDate: tuesday))
    #expect(line.mark == "Checked")
    #expect(line.detail == detail)
    #expect(line.tone == (attention ? .attention : .ok))
  }

  @Test func plainWordsWithNoDateOrTimeToName() {
    #expect(StopCheckLine(check(.shutThatDay))?.detail == "shut that day")
    #expect(StopCheckLine(check(.opensLater))?.detail == "opens later")
    #expect(StopCheckLine(check(.closesEarly))?.detail == "shuts early")
    #expect(StopCheckLine(check(.shutByThen))?.detail == "shut by then")
    #expect(StopCheckLine(check(.open))?.detail == "open")
  }

  @Test func anHoursValueThisBuildDoesNotKnowIsNeverReadAsOpen() {
    let line = StopCheckLine(check(.UNRECOGNIZED(99)))
    #expect(line?.detail == "hours vary")
    #expect(line?.tone == .ok)
  }

  @Test func aHolidayIsNamedAndItsUnknownHoursSaidSo() {
    #expect(StopCheckLine(check(.shutThatDay, holiday: "Natal"), dayDate: tuesday)?.detail == "shut Tue · Natal")
    let unknown = StopCheckLine(check(.open, closes: 1080, holiday: "Dia da Liberdade", holidayUnknown: true))
    #expect(unknown?.detail == "open until 18:00 · Dia da Liberdade, hours may differ")
    #expect(unknown?.explain.contains("public holiday") == true)
  }

  @Test func aDayCountsOnlyStopsTheMapAnsweredFor() {
    let stops = [
      stop(check(.open)), stop(check(.shutThatDay)), stop(check(status: .notFound)),
      stop(check(status: .unspecified)), stop(nil),
    ]
    let tally = DayCheckTally(stops: stops)
    #expect(tally.checked == 2)
    #expect(tally.total == 3)
    #expect(tally.needAttention == 1)
    #expect(tally.label == "2 of 3 checked · 1 needs a look")
  }

  @Test func aDayWithNothingCheckedSaysNothing() {
    #expect(DayCheckTally(stops: [stop(nil)]).label == nil)
    #expect(DayCheckTally(stops: [stop(check(.open))]).label == "1 of 1 checked")
  }

  @Test func aTripHasAShutStopOnlyWhenAPlaceWasFoundAndIsShutAllDay() {
    func trip(_ stops: [Loci_Trip_TripStop]) -> Loci_Trip_TripDraft {
      var day = Loci_Trip_TripDay()
      day.stops = stops
      var trip = Loci_Trip_TripDraft()
      trip.days = [Loci_Trip_TripDay(), day]
      return trip
    }
    #expect(trip([stop(check(.open)), stop(check(.shutThatDay))]).hasShutStop)
    #expect(!trip([stop(check(.opensLater)), stop(check(status: .notFound)), stop(nil)]).hasShutStop)
    #expect(!Loci_Trip_TripDraft().hasShutStop)
  }

  @Test func aPlannersCardIsTurnedDownNotTakenBack() {
    var fromPlanner = Loci_Chat_ActionProposal()
    fromPlanner.source = .chat
    var byHand = Loci_Chat_ActionProposal()
    byHand.source = .editor
    // The owner's own trip: the planner's card carries the owner as proposer.
    #expect(TripProposalsSection.dismissLabel(fromPlanner, isOwner: true, mine: true) == "Not now")
    #expect(TripProposalsSection.dismissLabel(byHand, isOwner: true, mine: true) == "Take back")
    #expect(TripProposalsSection.dismissLabel(byHand, isOwner: true, mine: false) == "Not now")
    #expect(TripProposalsSection.dismissLabel(byHand, isOwner: false, mine: true) == "Take back")
  }
}
