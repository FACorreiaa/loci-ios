import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Hotel comparison fixtures, as the server sends them.
enum HotelFixtures {
  static func stop(_ name: String, mode: Loci_Trip_TransitMode, lines: [String], minutes: Int32, routed: Bool) -> Loci_Trip_TransitStop {
    var stop = Loci_Trip_TransitStop()
    stop.name = name
    stop.mode = mode
    stop.lines = lines
    stop.walkMinutes = minutes
    stop.routed = routed
    return stop
  }

  static func hotel(_ name: String, city: String = "Barcelona", note: String = "", identified: Bool = true) -> Loci_Chat_ComparedHotel {
    var hotel = Loci_Chat_ComparedHotel()
    hotel.sourceURL = "https://www.booking.com/Share-abc"
    hotel.source = "booking.com"
    hotel.identified = identified
    hotel.stay.name = name
    hotel.stay.cityName = city
    hotel.userNote = note
    return hotel
  }

  static func report(id: String = "r1", proposal: String = "") -> Loci_Chat_HotelComparisonReport {
    var report = Loci_Chat_HotelComparisonReport()
    report.id = id
    report.cityName = "Barcelona"
    var verdi = hotel("Verdi 254", note: "385 euros with breakfast")
    verdi.nearbyStops = [
      stop("Gran de Gràcia", mode: .bus, lines: ["22", "24", "V17"], minutes: 3, routed: false),
      stop("Fontana", mode: .metro, lines: ["L3"], minutes: 6, routed: true),
    ]
    report.hotels = [verdi, hotel("Hotel X", note: "349 without breakfast")]
    report.verdict = "Verdi 254 is the better base."
    report.recommendedIndex = 0
    var row = Loci_Chat_ComparisonRow()
    row.label = "Breakfast"
    row.values = ["Included"]
    report.rows = [row]
    report.stayProposalID = proposal
    return report
  }

  static func event(_ report: Loci_Chat_HotelComparisonReport, id: String) -> Loci_Chat_StreamEvent {
    var event = Loci_Chat_StreamEvent()
    event.eventID = id
    event.hotelComparison.report = report
    return event
  }

  static func stayProposal(_ id: String, trip: String = "t1") -> Loci_Chat_ActionProposal {
    var proposal = Loci_Chat_ActionProposal()
    proposal.id = id
    proposal.tripID = trip
    proposal.action.chooseStay.cityName = "Barcelona"
    proposal.action.chooseStay.reportID = "r1"
    return proposal
  }

  static func proposalEvent(_ proposal: Loci_Chat_ActionProposal, id: String) -> Loci_Chat_StreamEvent {
    var event = Loci_Chat_StreamEvent()
    event.eventID = id
    event.actionProposal.proposal = proposal
    return event
  }
}

extension Loci_Assistant_AssistantEvent {
  static func hotelReport(_ report: Loci_Chat_HotelComparisonReport) -> Self {
    var event = Self()
    event.event = .hotelReport(report)
    return event
  }

  static func trip(_ trip: Loci_Chat_ActionProposal, awaitsOwner: Bool = false) -> Self {
    var proposal = Loci_Assistant_Proposal()
    proposal.kind = .trip(trip)
    proposal.awaitsOwner = awaitsOwner
    var event = Self()
    event.event = .proposal(proposal)
    return event
  }
}

struct HotelCompareTests {
  // MARK: - Main chat

  @Test func theRequestSaysThisBuildDrawsHotelComparisons() async {
    let envelope = SearchEnvelope(requestId: "r", query: "which one?", startedAt: .now, finished: false, notified: false)
    let fresh = await SearchSessionController.request(from: envelope, resuming: false)
    #expect(fresh.capabilities == [.hotelComparison])
    var resumed = envelope
    resumed.sessionId = "s1"
    resumed.lastEventId = "e3"
    #expect(await SearchSessionController.request(from: resumed, resuming: true).capabilities == [.hotelComparison])
  }

  @Test func aHotelComparisonEventIsTheAnswer() {
    var state = SearchState()
    state.apply(Events.start("s1", domain: .accommodation, city: "Barcelona"))
    #expect(!state.hasResult)
    #expect(state.phase == .skeleton)

    state.apply(HotelFixtures.event(HotelFixtures.report(proposal: "p1"), id: "e1"))
    #expect(state.hotelReport?.hotels.map(\.stay.name) == ["Verdi 254", "Hotel X"])
    // A report alone is a result, but not places to save or share.
    #expect(state.hasResult)
    #expect(!state.hasPlaceResult)
    #expect(state.places.isEmpty)

    state.apply(HotelFixtures.proposalEvent(HotelFixtures.stayProposal("p1"), id: "e2"))
    #expect(state.stayProposal?.id == "p1")

    #expect(state.apply(Events.complete("s1", id: "e3")) == .completed)
    #expect(state.status == .completed)
    #expect(state.phase == .done)
    #expect(!state.needsSessionFetch)
  }

  @Test func aReplayedReportIsAppliedOnce() {
    var state = SearchState()
    let event = HotelFixtures.event(HotelFixtures.report(), id: "e1")
    state.apply(event)
    var changed = HotelFixtures.report()
    changed.verdict = "Replayed"
    state.apply(HotelFixtures.event(changed, id: "e1"))
    #expect(state.hotelReport?.verdict == "Verdi 254 is the better base.")
  }

  @Test func anEmptyReportIsNotAResult() {
    var state = SearchState()
    state.apply(HotelFixtures.event(Loci_Chat_HotelComparisonReport(), id: "e1"))
    #expect(state.hotelReport == nil)
    #expect(!state.hasResult)
  }

  @Test func anErrorAfterTheReportKeepsIt() {
    var state = SearchState()
    state.apply(HotelFixtures.event(HotelFixtures.report(), id: "e1"))
    state.apply(Events.error("Something broke", id: "e2"))
    #expect(state.status == .completedWithError("Something broke"))
    #expect(state.hotelReport != nil)
  }

  @Test func aReportWithoutItsProposalAsksWhichTrip() {
    var state = SearchState()
    state.apply(HotelFixtures.event(HotelFixtures.report(proposal: "p1"), id: "e1"))
    #expect(state.stayProposal == nil)  // named, but not received
    state.apply(HotelFixtures.proposalEvent(HotelFixtures.stayProposal("other"), id: "e2"))
    #expect(state.stayProposal == nil)
    var none = SearchState()
    none.apply(HotelFixtures.event(HotelFixtures.report(proposal: ""), id: "e1"))
    none.apply(HotelFixtures.proposalEvent(HotelFixtures.stayProposal(""), id: "e2"))
    #expect(none.stayProposal == nil)  // an empty id names nothing
  }

  @Test func theReportSurvivesOnThisPhone() {
    let store = SearchStore(directory: FileManager.default.temporaryDirectory.appending(path: "hotel-report-tests-\(UUID().uuidString)"))
    var state = SearchState()
    state.apply(Events.start("s1", domain: .accommodation, city: "Barcelona"))
    state.apply(HotelFixtures.event(HotelFixtures.report(proposal: "p1"), id: "e1"))
    state.apply(Events.complete("s1", id: "e2"))
    store.saveResult(state)

    let link = SessionLink(destination: .hotels, sessionId: "s1", cityName: "Barcelona", domain: "accommodation")
    let restored = store.loadResult(for: link)
    #expect(restored?.hotelReport == state.hotelReport)
    #expect(restored?.hasResult == true)
    #expect(restored?.stayProposal == nil)

    // A later turn in the session without a report takes the old one away.
    var next = SearchState()
    next.apply(Events.start("s1", domain: .accommodation, city: "Barcelona"))
    next.apply(Events.hotels(["Hotel A"], id: "e1"))
    store.saveResult(next)
    #expect(store.loadResult(for: link)?.hotelReport == nil)
  }

  // MARK: - Overlay

  @Test func theProposalForAReportBecomesItsAddButtons() {
    var turn = AskLociTurn(id: 1, you: "Which one?")
    turn.apply(.hotelReport(HotelFixtures.report(proposal: "p1")))
    turn.apply(.trip(HotelFixtures.stayProposal("p1")))
    #expect(turn.cards.count == 1)
    guard case .hotelReport(let card) = turn.cards.first else {
      Issue.record("expected a report card")
      return
    }
    #expect(card.proposal?.id == "p1")
    #expect(!card.awaitsOwner)
    #expect(card.report.hotels.count == 2)
  }

  @Test func aProposalThatArrivesFirstIsStillFolded() {
    var turn = AskLociTurn(id: 1, you: "Which one?")
    turn.apply(.trip(HotelFixtures.stayProposal("p1"), awaitsOwner: true))
    turn.apply(.hotelReport(HotelFixtures.report(proposal: "p1")))
    #expect(turn.cards.count == 1)
    guard case .hotelReport(let card) = turn.cards.first else {
      Issue.record("expected a report card")
      return
    }
    #expect(card.proposal?.id == "p1")
    #expect(card.awaitsOwner)
  }

  @Test func anotherProposalStaysItsOwnCard() {
    var turn = AskLociTurn(id: 1, you: "Which one?")
    turn.apply(.hotelReport(HotelFixtures.report(proposal: "p1")))
    turn.apply(.trip(HotelFixtures.stayProposal("p2")))
    #expect(turn.cards.map(\.id) == ["hotel-report-r1", "p2"])

    var bare = AskLociTurn(id: 2, you: "Which one?")
    bare.apply(.hotelReport(HotelFixtures.report(proposal: "")))
    bare.apply(.trip(HotelFixtures.stayProposal("")))
    #expect(bare.cards.count == 2)  // no id to fold on
  }

  @Test func confirmingKeepsTheReportAndSaysWhatHappened() {
    var turn = AskLociTurn(id: 1, you: "Which one?")
    turn.apply(.hotelReport(HotelFixtures.report(proposal: "p1")))
    turn.apply(.trip(HotelFixtures.stayProposal("p1")))
    turn.settleCard("p1", note: "Verdi 254 is your stay in Barcelona.")
    guard case .hotelReport(let card) = turn.cards.first else {
      Issue.record("expected the report to stay")
      return
    }
    #expect(card.confirmation == "Verdi 254 is your stay in Barcelona.")
    #expect(card.proposal?.tripID == "t1")

    // Turned down, the report goes back to asking which trip.
    turn.settleCard("p1", note: nil)
    guard case .hotelReport(let after) = turn.cards.first else {
      Issue.record("expected the report to stay")
      return
    }
    #expect(after.proposal == nil)
  }

  // MARK: - The card's words

  @Test func titleAndRecommendation() {
    let report = HotelFixtures.report()
    #expect(HotelReport.title(report) == "Verdi 254 vs Hotel X · Barcelona")
    #expect(HotelReport.recommendedIndex(report) == 0)
    var none = report
    none.clearRecommendedIndex()
    #expect(HotelReport.recommendedIndex(none) == nil)
    var outOfRange = report
    outOfRange.recommendedIndex = 7
    #expect(HotelReport.recommendedIndex(outOfRange) == nil)
  }

  @Test func theTableLeadsWithWhatTheTravellerWrote() {
    let rows = HotelReport.rows(HotelFixtures.report())
    #expect(rows.map(\.label) == ["You said", "Breakfast", "Nearest stop"])
    #expect(rows[0].values == ["385 euros with breakfast", "349 without breakfast"])
    // A row short of a value, and a hotel with no stops, get a dash.
    #expect(rows[1].values == ["Included", "—"])
    // The nearest stop is the shortest walk, and an unrouted one says so.
    #expect(rows[2].values == ["Gran de Gràcia · 22, 24, V17 · 3 min walk (estimate)", "—"])
  }

  @Test func rowsNobodyHasAnythingForAreLeftOut() {
    var report = HotelFixtures.report()
    report.rows = []
    for index in report.hotels.indices {
      report.hotels[index].userNote = ""
      report.hotels[index].nearbyStops = []
    }
    #expect(HotelReport.rows(report).isEmpty)
  }

  @Test func anUnidentifiedHotelIsShownButOnlyAddedWithAName() {
    let known = HotelFixtures.hotel("Verdi 254", identified: false)
    #expect(HotelReport.name(known, at: 1) == "Verdi 254")
    #expect(HotelReport.canAdd(known))
    let unknown = HotelFixtures.hotel("", identified: false)
    #expect(HotelReport.name(unknown, at: 1) == "Hotel 2")
    #expect(!HotelReport.canAdd(unknown))
    #expect(!HotelReport.canAdd(HotelFixtures.hotel("Verdi 254", city: "")))
  }

  @Test func onlyHttpsSourcesOpen() {
    var report = HotelFixtures.report()
    var good = Loci_Chat_ReportSource()
    good.title = "Gràcia guide"
    good.publisher = "Time Out"
    good.url = "https://www.timeout.com/barcelona"
    var plain = Loci_Chat_ReportSource()
    plain.title = "Old page"
    plain.url = "http://example.com"
    var script = Loci_Chat_ReportSource()
    script.title = "Odd"
    script.url = "javascript:alert(1)"
    report.sources = [good, plain, script]
    let sources = HotelReport.sources(report)
    #expect(sources.map(\.text) == ["Gràcia guide — Time Out", "Old page", "Odd"])
    #expect(sources.map { $0.url?.absoluteString } == ["https://www.timeout.com/barcelona", nil, nil])
    #expect(TransitFormat.httpsURL("https://") == nil)
    #expect(TransitFormat.httpsURL("  https://maps.apple.com/?daddr=1,2 ") != nil)
  }

  @Test func aLivePriceIsSaidInItsOwnCurrency() {
    var price = Loci_Chat_LivePrice()
    price.nightlyMinor = 12_800
    price.totalMinor = 38_500
    price.currency = "EUR"
    price.provider = "LiteAPI"
    let line = HotelReport.livePrice(price, locale: Locale(identifier: "en_GB"))
    #expect(line == "€128.00 a night · €385.00 in all · via LiteAPI")
    price.currency = ""
    #expect(HotelReport.livePrice(price) == nil)
    var empty = Loci_Chat_LivePrice()
    empty.currency = "EUR"
    #expect(HotelReport.livePrice(empty) == nil)
  }

  // MARK: - Add to trip

  @MainActor @Test func addStateFollowsThePickerThenTheProposal() {
    let names = ["Verdi 254", "Hotel X"]
    #expect(HotelReportCard.addState(picked: nil, proposal: nil, tapped: nil, names: names, confirmation: nil) == .ready)
    #expect(HotelReportCard.addState(picked: nil, proposal: .applying, tapped: 1, names: names, confirmation: nil) == .adding(1))
    #expect(HotelReportCard.addState(picked: nil, proposal: .failed("Gone"), tapped: 1, names: names, confirmation: nil) == .failed("Gone"))
    #expect(
      HotelReportCard.addState(picked: nil, proposal: .applied, tapped: 0, names: names, confirmation: nil)
        == .added("Verdi 254 is now your stay.")
    )
    #expect(
      HotelReportCard.addState(picked: nil, proposal: .applied, tapped: 0, names: names, confirmation: "Done by the server.")
        == .added("Done by the server.")
    )
    #expect(HotelReportCard.addState(picked: nil, proposal: .applied, tapped: nil, names: names, confirmation: nil) == .added("Added to your trip."))
    // A trip picked by hand wins over a proposal that failed.
    #expect(
      HotelReportCard.addState(picked: "Picked.", proposal: .failed("Gone"), tapped: 0, names: names, confirmation: nil) == .added("Picked.")
    )
  }

  @MainActor @Test func theChatAppliesAgainstTheVersionItJustRead() async {
    let stub = StaleThenFreshTripActions(staleCount: 0)
    let model = TripActionsModel(service: stub)
    let applied = await model.applyReadingVersion(HotelFixtures.stayProposal("p1"), option: 1) { 7 }
    #expect(applied)
    #expect(model.state("p1") == .applied)
    #expect(await stub.versions == [7])
    #expect(await stub.options == [1])
  }

  @MainActor @Test func aStaleApplyReadsTheVersionAgainOnce() async {
    let stub = StaleThenFreshTripActions(staleCount: 1)
    let model = TripActionsModel(service: stub)
    let versions = VersionCounter(start: 3)
    let applied = await model.applyReadingVersion(HotelFixtures.stayProposal("p1"), option: 0) { await versions.next() }
    #expect(applied)
    #expect(await stub.versions == [3, 4])
    #expect(!model.needsReload)

    let stuck = StaleThenFreshTripActions(staleCount: 5)
    let second = TripActionsModel(service: stuck)
    #expect(await second.applyReadingVersion(HotelFixtures.stayProposal("p2"), option: 0) { await versions.next() } == false)
    #expect(await stuck.versions.count == 2)  // gives up after the second refusal
    if case .failed = second.state("p2") {} else { Issue.record("expected failed") }
  }

  @MainActor @Test func aTripThatWillNotLoadIsNotApplied() async {
    let stub = StaleThenFreshTripActions(staleCount: 0)
    let model = TripActionsModel(service: stub)
    #expect(await model.applyReadingVersion(HotelFixtures.stayProposal("p1"), option: 0) { nil } == false)
    #expect(await stub.versions.isEmpty)
    #expect(model.state("p1") == .failed("Couldn't load the trip. Try again."))
  }

  @MainActor @Test func chooseStayIsAPickLikeAHotelSearch() {
    #expect(TripProposalsSection.needsPick(HotelFixtures.stayProposal("p1")))
    var dates = Loci_Chat_ActionProposal()
    dates.action.setDates.startDate = "2026-12-01"
    #expect(!TripProposalsSection.needsPick(dates))
  }

  // MARK: - Analytics

  @Test func analyticsCarryCountsNeverWords() {
    var report = HotelFixtures.report(proposal: "p1")
    report.hotels[1].identified = false
    let shown = HotelCompareAnalytics.reportShownProperties(.overlay, report, hasProposal: true)
    #expect(shown["surface"] as? String == "overlay")
    #expect(shown["hotels"] as? Int == 2)
    #expect(shown["identified"] as? Int == 1)
    #expect(shown["has_verdict"] as? Bool == true)
    #expect(shown["has_recommendation"] as? Bool == true)
    #expect(shown["has_trip"] as? Bool == true)

    var hotel = report.hotels[0]
    hotel.stay.latitude = 41.4
    hotel.stay.longitude = 2.15
    let set = HotelCompareAnalytics.staySetProperties(.chat, via: .picker, hotel: hotel)
    #expect(set["via"] as? String == "picker")
    #expect(set["has_coordinates"] as? Bool == true)

    let tapped = HotelCompareAnalytics.addTappedProperties(.planner, via: .proposal, option: 1, recommended: false)
    let opened = HotelCompareAnalytics.directionsProperties(target: "day", provider: "apple", source: "trip", suggestedMode: "https://x.y")
    #expect(opened["suggested_mode"] == nil)  // only the server's two values pass
    for properties in [shown, set, tapped, opened] {
      for value in properties.values {
        guard let text = value as? String else { continue }
        #expect(!text.contains("Verdi") && !text.contains("Barcelona") && !text.contains("http") && !text.contains("euros"))
      }
    }
  }
}

/// Refuses the first `staleCount` applies as stale, then accepts.
private actor StaleThenFreshTripActions: TripActionService {
  private var staleCount: Int
  private(set) var versions: [Int64] = []
  private(set) var options: [Int?] = []

  init(staleCount: Int) { self.staleCount = staleCount }

  func apply(proposalID: String, option: Int?, baseVersion: Int64) async throws(TripActionError) -> Loci_Chat_ApplyTripActionResponse {
    versions.append(baseVersion)
    options.append(option)
    if staleCount > 0 {
      staleCount -= 1
      throw TripActionError(kind: .stale, message: "trip version conflict")
    }
    return Loci_Chat_ApplyTripActionResponse()
  }

  func dismiss(proposalID: String) async throws(TripActionError) {}
}

private actor VersionCounter {
  private var value: Int64

  init(start: Int64) { value = start }

  func next() -> Int64 {
    defer { value += 1 }
    return value
  }
}
