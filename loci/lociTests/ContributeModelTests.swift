import CoreLocation
import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

/// Contribute (parity pass 2, Phase 6). The server corroborates claims on
/// exact strings, so these port web's `lib/place-facts/place-facts.test.ts`
/// and `lib/contribute/paginate.test.ts` one to one, plus FieldPicker's rules.
struct ContributeModelTests {
  // Each answer is filed separately so it corroborates on its own.
  @Test func sendsOneClaimPerAnswerForMultiAnswerField() {
    #expect(PlaceFactVocabulary.claimValues(.dietary, tokens: ["vegan", "gluten_free"]) == ["gluten_free", "vegan"])
  }

  @Test func ordersAnswersTheSameWayHoweverPicked() {
    #expect(
      PlaceFactVocabulary.claimValues(.dietary, tokens: ["vegan", "gluten_free"])
        == PlaceFactVocabulary.claimValues(.dietary, tokens: ["gluten_free", "vegan"])
    )
  }

  @Test func deDuplicatesAndLowercases() {
    #expect(PlaceFactVocabulary.claimValues(.dietary, tokens: ["Vegan", "vegan", " HALAL "]) == ["halal", "vegan"])
  }

  @Test func dropsEmptyEntries() { #expect(PlaceFactVocabulary.claimValues(.dietary, tokens: ["vegan", "", "  "]) == ["vegan"]) }

  @Test func sendsSingleClaimForSingleAnswerField() {
    #expect(PlaceFactVocabulary.claimValues(.crowdLevel, tokens: ["busy"]) == ["busy"])
    // Only the first survives, after sorting (web: cleaned[0]).
    #expect(PlaceFactVocabulary.claimValues(.crowdLevel, tokens: ["quiet", "busy"]) == ["busy"])
  }

  @Test func sendsNothingWhenNothingSelected() { #expect(PlaceFactVocabulary.claimValues(.dietary, tokens: []).isEmpty) }
}

struct VocabularyTests {
  @Test func coversEveryContributableField() {
    for field in PlaceFactVocabulary.contributableFields { #expect(PlaceFactVocabulary.vocabulary(for: field) != nil) }
    #expect(PlaceFactVocabulary.vocabulary(for: .unspecified) == nil)
  }

  @Test func givesEveryChoiceFieldAtLeastTwoOptions() {
    for field in PlaceFactVocabulary.contributableFields {
      guard let vocabulary = PlaceFactVocabulary.vocabulary(for: field), vocabulary.kind != .structured else { continue }
      #expect(vocabulary.options.count > 1)
    }
  }

  @Test func usesWireSafeTokens() {
    for field in PlaceFactVocabulary.contributableFields {
      for option in PlaceFactVocabulary.vocabulary(for: field)?.options ?? [] {
        #expect(option.token.wholeMatch(of: /[a-z0-9_]+/) != nil, "\(option.token)")
      }
    }
  }

  /// The token lists in loci-connect-server/internal/domain/placeintel/values.go.
  @Test func tokensMatchTheServerTable() {
    let server: [Loci_Place_PlaceFactField: [String]] = [
      .crowdLevel: ["quiet", "moderate", "busy", "packed"], .noiseLevel: ["quiet", "conversational", "lively", "loud"],
      .priceLevel: ["budget", "moderate", "pricey", "splurge"], .childFriendly: ["yes", "limited", "no"],
      .dogFriendly: ["yes", "outdoor_only", "no"], .dietary: ["vegetarian", "vegan", "gluten_free", "halal", "kosher", "none"],
      .accessibility: ["step_free", "accessible_wc", "lift", "wide_doors", "tactile", "none"],
      .vibe: ["cosy", "lively", "romantic", "touristy", "local", "quiet", "work_friendly", "outdoorsy"],
    ]
    for (field, tokens) in server { #expect(PlaceFactVocabulary.vocabulary(for: field)?.options.map(\.token) == tokens) }
    #expect(PlaceFactVocabulary.vocabulary(for: .openingHours)?.kind == .structured)
    #expect(PlaceFactVocabulary.vocabulary(for: .vibe)?.maxSelections == 3)
  }

  @Test func offersFieldsInWebOrder() {
    #expect(
      PlaceFactVocabulary.contributableFields == [
        .openingHours, .priceLevel, .accessibility, .dietary, .crowdLevel, .noiseLevel, .childFriendly, .dogFriendly, .vibe,
      ]
    )
  }

  @Test func labelsAndQuestionsMatchWeb() {
    #expect(PlaceFactVocabulary.label(.openingHours) == "Opening Hours")
    #expect(PlaceFactVocabulary.label(.childFriendly) == "Child Friendly")
    #expect(PlaceFactVocabulary.label(.vibe) == "Vibe")
    #expect(PlaceFactVocabulary.question(.noiseLevel) == "How loud was it?")
    #expect(PlaceFactVocabulary.question(.unspecified) == "What is true right now?")
    #expect(PlaceFactVocabulary.wireName(.dogFriendly) == "PLACE_FACT_FIELD_DOG_FRIENDLY")
  }

  @Test func storedFactsReadAsTheirLabels() {
    #expect(PlaceFactVocabulary.displayValue(.dietary, "gluten_free") == "Gluten free")
    #expect(PlaceFactVocabulary.displayValue(.noiseLevel, "quiet") == "You can whisper")
    #expect(PlaceFactVocabulary.displayValue(.openingHours, "mon-sun closed") == "mon-sun closed")
    #expect(PlaceFactVocabulary.displayValue(.vibe, "unknown_token") == "unknown_token")
  }
}

/// web: FieldPicker's applyExclusivity and the VIBE cap, and the single-choice toggle.
struct FieldSelectionTests {
  @Test func singleChoicePicksAndClears() {
    #expect(PlaceFactVocabulary.toggle("busy", in: [], field: .crowdLevel) == ["busy"])
    #expect(PlaceFactVocabulary.toggle("quiet", in: ["busy"], field: .crowdLevel) == ["quiet"])
    #expect(PlaceFactVocabulary.toggle("busy", in: ["busy"], field: .crowdLevel).isEmpty)
  }

  @Test func noneClearsTheRest() { #expect(PlaceFactVocabulary.toggle("none", in: ["vegan", "halal"], field: .dietary) == ["none"]) }

  @Test func anythingElseClearsNone() { #expect(PlaceFactVocabulary.toggle("vegan", in: ["none"], field: .dietary) == ["vegan"]) }

  @Test func tappingAPickedAnswerRemovesIt() {
    #expect(PlaceFactVocabulary.toggle("vegan", in: ["vegan", "halal"], field: .dietary) == ["halal"])
    #expect(PlaceFactVocabulary.toggle("none", in: ["none"], field: .accessibility).isEmpty)
  }

  @Test func vibeDropsTheOldestPastThree() {
    let three = ["cosy", "local", "quiet"]
    #expect(PlaceFactVocabulary.toggle("lively", in: three, field: .vibe) == ["local", "quiet", "lively"])
  }

  @Test func uncappedMultiKeepsEveryAnswer() {
    let four = ["step_free", "accessible_wc", "lift", "wide_doors"]
    #expect(PlaceFactVocabulary.toggle("tactile", in: four, field: .accessibility).count == 5)
  }

  @Test func openingHoursIsNotATokenField() { #expect(PlaceFactVocabulary.toggle("x", in: [], field: .openingHours).isEmpty) }
}

struct OpeningHoursTests {
  private func week(_ overrides: [HoursDay: DayHours] = [:]) -> OpeningHours {
    var hours = OpeningHours.default
    for (day, value) in overrides { hours[day] = value }
    return hours
  }

  private func open(_ spans: (String, String)...) -> DayHours { .open(spans.map { HoursInterval(start: $0.0, end: $0.1) }) }

  // MARK: encode

  @Test func collapsesConsecutiveDaysWithIdenticalHours() { #expect(OpeningHours.default.encoded == "mon-fri 09:00-17:00; sat-sun closed") }

  @Test func keepsALoneDayUngrouped() {
    #expect(week([.sat: open(("10:00", "14:00"))]).encoded == "mon-fri 09:00-17:00; sat 10:00-14:00; sun closed")
  }

  @Test func sortsAndMergesOverlappingIntervalsWithinADay() {
    let hours = week([.sat: open(("19:00", "23:00"), ("12:00", "15:00"), ("14:00", "16:00"))])
    #expect(hours.encoded == "mon-fri 09:00-17:00; sat 12:00-16:00,19:00-23:00; sun closed")
  }

  // Two scouts entering the same week in a different order are the case this exists for.
  @Test func producesOneStringForOneWeekHoweverEntered() {
    let first = week([.sat: open(("12:00", "15:00"), ("19:00", "24:00"))])
    let second = week([.sat: open(("19:00", "24:00"), ("12:00", "15:00"))])
    #expect(first.encoded == second.encoded)
  }

  @Test func treatsADayWithNoIntervalsAsClosed() { #expect(week([.sat: .open([])]).encoded == "mon-fri 09:00-17:00; sat-sun closed") }

  @Test func mergesTouchingIntervals() {
    #expect(week([.sat: open(("10:00", "12:00"), ("12:00", "14:00"))]).encoded == "mon-fri 09:00-17:00; sat 10:00-14:00; sun closed")
  }

  // MARK: parse

  @Test func roundTripsTheCanonicalForm() throws {
    let encoded = OpeningHours.default.encoded
    let parsed = try #require(OpeningHours.parse(encoded))
    #expect(parsed.encoded == encoded)
  }

  @Test func expandsADayRangeAcrossEveryDayItCovers() throws {
    let parsed = try #require(OpeningHours.parse("mon-sun 00:00-24:00"))
    for day in HoursDay.allCases { #expect(parsed[day] == .open([HoursInterval(start: "00:00", end: "24:00")])) }
  }

  @Test func rejectsProseAndPartialWeeksRatherThanGuessing() {
    #expect(OpeningHours.parse("9am-5pm") == nil)
    #expect(OpeningHours.parse("mon 09:00-17:00") == nil)
    #expect(OpeningHours.parse("funday 09:00-17:00") == nil)
    #expect(OpeningHours.parse("fri-mon 09:00-17:00") == nil)
    #expect(OpeningHours.parse("mon-sun 25:00-26:00") == nil)
  }

  // MARK: validity

  @Test func acceptsTheDefaultWeek() { #expect(OpeningHours.default.isValid) }

  @Test func rejectsASpanThatEndsBeforeItStarts() { #expect(!week([.mon: open(("17:00", "09:00"))]).isValid) }

  @Test func rejectsAnOpenDayWithNoHours() { #expect(!week([.mon: .open([])]).isValid) }

  @Test func acceptsMidnightAsAClose() {
    #expect(week([.fri: open(("18:00", "24:00"))]).isValid)
    #expect(!week([.fri: open(("24:00", "24:00"))]).isValid)
  }

  // MARK: editing

  @Test func editsTheFirstIntervalOnly() {
    var hours = week([.sat: open(("10:00", "12:00"), ("19:00", "23:00"))])
    hours.setTime(.sat, start: false, to: "13:30")
    #expect(hours[.sat] == open(("10:00", "13:30"), ("19:00", "23:00")))
    hours.setTime(.sun, start: true, to: "08:00")
    #expect(hours[.sun] == .closed)
    hours.setTime(.mon, start: true, to: "nope")
    #expect(hours[.mon] == open(("09:00", "17:00")))
  }

  @Test func reopeningADayStartsAtNineToFive() {
    var hours = OpeningHours.default
    hours.toggleClosed(.sun)
    #expect(hours[.sun] == open(("09:00", "17:00")))
    hours.toggleClosed(.mon)
    #expect(hours[.mon] == .closed)
  }

  /// The picker round-trip is fixed to GMT, so no device zone or DST can shift a time.
  @Test func clockRoundTripsInAnyZone() {
    for time in ["00:00", "09:05", "17:30", "23:59"] { #expect(OpeningHours.clockString(OpeningHours.clockDate(time)) == time) }
  }
}

struct TaskPagingTests {
  @Test func pageCountIsOneForAnEmptyList() { #expect(TaskPaging.pageCount(0) == 1) }
  @Test func fitsFivePlacesOnOnePage() { #expect(TaskPaging.pageCount(TaskPaging.tasksPerPage) == 1) }
  @Test func opensASecondPageOnTheSixthPlace() { #expect(TaskPaging.pageCount(TaskPaging.tasksPerPage + 1) == 2) }

  @Test func clampPullsTooSmallUpToOne() {
    #expect(TaskPaging.clamp(0, total: 12) == 1)
    #expect(TaskPaging.clamp(-2, total: 12) == 1)
  }

  @Test func clampPullsTooLargeBackToTheLastPage() { #expect(TaskPaging.clamp(9, total: 12) == 3) }
  @Test func clampKeepsAValidPage() { #expect(TaskPaging.clamp(2, total: 12) == 2) }

  @Test func sliceReturnsTheRightItems() {
    let places = ["a", "b", "c", "d", "e", "f", "g"]
    #expect(TaskPaging.slice(places, page: 1) == ["a", "b", "c", "d", "e"])
    #expect(TaskPaging.slice(places, page: 2) == ["f", "g"])
    #expect(TaskPaging.slice(places, page: 99) == ["f", "g"])
    #expect(TaskPaging.slice([String](), page: 1).isEmpty)
  }

  @Test func rangeIsOneIndexedAndInclusive() {
    #expect(TaskPaging.range(page: 1, total: 0) == (0, 0))
    #expect(TaskPaging.range(page: 1, total: 12) == (1, 5))
    #expect(TaskPaging.range(page: 3, total: 12) == (11, 12))
  }

  @Test func pageOfIndex() {
    #expect(TaskPaging.pageOf(0) == 1)
    #expect(TaskPaging.pageOf(5) == 2)
    #expect(TaskPaging.pageOf(-1) == 1)
  }
}

struct ResolveTaskTests {
  @Test func fromPlaceOpensEveryField() {
    let task = VerificationTask.fromPlace(id: "poi-1", name: "Café Alentejo")
    #expect(task == VerificationTask(poiID: "poi-1", poiName: "Café Alentejo", requestedFields: PlaceFactVocabulary.contributableFields))
  }

  @Test func keepsTheGapListFieldsWhenAlreadyQueued() {
    let queued = VerificationTask(poiID: "poi-1", poiName: "Café Alentejo", requestedFields: [.noiseLevel])
    #expect(VerificationTask.resolve(id: "poi-1", name: "Café Alentejo", in: [queued]) == queued)
  }

  @Test func opensEveryFieldWhenNotOnTheGapList() {
    #expect(VerificationTask.resolve(id: "poi-9", name: "Miradouro", in: []).requestedFields == PlaceFactVocabulary.contributableFields)
  }

  @Test func dropsFieldsThisBuildCannotAsk() {
    var proto = Loci_Place_VerificationTask()
    proto.poiID = "poi-1"
    proto.poiName = "Café"
    proto.requestedFields = [.unspecified, .vibe, .UNRECOGNIZED(42)]
    #expect(VerificationTask(proto).requestedFields == [.vibe])
    #expect(VerificationTask(proto).oldestFactAt == nil)
  }
}

struct ClaimOutcomeTests {
  @Test func bestIsAcceptedThenPendingThenFirst() {
    let pending = ClaimResult(claimID: "p", status: .pending)
    let accepted = ClaimResult(claimID: "a", status: .accepted)
    let contradicted = ClaimResult(claimID: "c", status: .contradicted)
    #expect(ClaimResult.best([pending, accepted, contradicted]) == accepted)
    #expect(ClaimResult.best([contradicted, pending]) == pending)
    #expect(ClaimResult.best([contradicted, ClaimResult(claimID: "e", status: .expired)]) == contradicted)
    #expect(ClaimResult.best([]) == .empty)
  }

  @Test func statusReadsAsWebWordsAndCard() {
    #expect(ClaimResult(claimID: "", status: .accepted).statusName == "ACCEPTED")
    #expect(ClaimResult(claimID: "", status: .unspecified).statusName == "UNSPECIFIED")
    #expect(ClaimOutcome(.accepted) == .verified)
    #expect(ClaimOutcome(.contradicted) == .contradicted)
    #expect(ClaimOutcome(.pending) == .recorded(pending: true))
    #expect(ClaimOutcome(.expired) == .recorded(pending: false))
  }

  @Test func badgesReadAsWords() {
    #expect(ScoutBadge.title("local-scout") == "Local scout")
    #expect(ScoutBadge.title("night_owl") == "Night owl")
    #expect(ScoutBadge.detail("local-scout") != nil)
  }
}

struct ContributePayloadTests {
  private static let uuid = "5f0c0000-0000-4000-8000-000000000001"

  @Test func onlyStoredPlacesTakeReports() {
    #expect(ContributePayload.canReport(poiID: Self.uuid))
    #expect(!ContributePayload.canReport(poiID: "Café Alentejo"))
    #expect(!ContributePayload.canReport(poiID: "00000000-0000-0000-0000-000000000000"))
  }

  @Test func claimCarriesAFreshIDAndNow() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let request = ContributePayload.claim(poiID: Self.uuid, field: .vibe, value: "cosy", now: now, clientClaimID: "id-1")
    #expect(request.clientClaimID == "id-1")
    #expect(request.poiID == Self.uuid)
    #expect(request.field == .vibe)
    #expect(request.value == "cosy")
    #expect(request.observedAt.date == now)
    let first = ContributePayload.claim(poiID: Self.uuid, field: .vibe, value: "cosy")
    let second = ContributePayload.claim(poiID: Self.uuid, field: .vibe, value: "cosy")
    #expect(first.clientClaimID != second.clientClaimID)
    #expect(UUID(uuidString: first.clientClaimID) != nil)
  }

  @Test func listLimitsMatchWeb() {
    #expect(ContributePayload.tasks().limit == 40)
    #expect(ContributePayload.pendingPlaces().limit == 20)
  }

  @Test func searchIsHybridWithinTwentyFiveKmWhenLocated() throws {
    let here = CLLocationCoordinate2D(latitude: 38.71, longitude: -9.14)
    let request = try #require(ContributePayload.search(query: " cafe ", city: "", coordinate: here))
    #expect(request.query == "cafe")
    #expect(request.searchType == "hybrid")
    #expect(request.radiusKm == 25)
    #expect(request.latitude == 38.71)
    #expect(request.longitude == -9.14)
    // The validator needs a city even though a hybrid search ignores it.
    #expect(request.cityName == ContributePayload.nearbyCityPlaceholder)
    #expect(ContributePayload.search(query: "cafe", city: "Lisbon", coordinate: here)?.cityName == "Lisbon")
  }

  @Test func searchIsSemanticInTheCityOtherwise() throws {
    let request = try #require(ContributePayload.search(query: "cafe", city: " Porto ", coordinate: nil))
    #expect(request.searchType == "semantic")
    #expect(request.cityName == "Porto")
    #expect(!request.hasRadiusKm)
  }

  @Test func searchNeedsAQueryAndALocationOrCity() {
    #expect(ContributePayload.search(query: "  ", city: "Lisbon", coordinate: nil) == nil)
    #expect(ContributePayload.search(query: "cafe", city: " ", coordinate: nil) == nil)
  }

  @Test func submitPlaceTrimsAndOmitsAnEmptyKind() {
    let draft = PlaceDraft(name: "  Tasca  ", cityName: " Lisbon ", category: "  ", makeID: { "draft-1" })
    let request = ContributePayload.submitPlace(draft)
    #expect(request.clientSubmissionID == "draft-1")
    #expect(request.name == "Tasca")
    #expect(request.cityName == "Lisbon")
    #expect(!request.hasCategory)
    #expect(ContributePayload.submitPlace(PlaceDraft(name: "Tasca", cityName: "Lisbon", category: "bar")).category == "bar")
  }
}

struct PlaceDraftTests {
  @Test func keepsItsIDWhileTheDraftIsUnchanged() {
    var draft = PlaceDraft(name: "Tasca", cityName: "Lisbon")
    let id = draft.submissionID
    draft.setName("Tasca")
    draft.setCityName("Lisbon")
    #expect(draft.submissionID == id)
  }

  @Test func anyChangeMakesANewDraft() {
    var draft = PlaceDraft(name: "Tasca", cityName: "Lisbon")
    let first = draft.submissionID
    draft.setCategory("bar")
    #expect(draft.submissionID != first)
    let second = draft.submissionID
    draft.setName("Tasca do Chico")
    #expect(draft.submissionID != second)
  }

  @Test func readinessNeedsTwoCharactersAndACity() {
    #expect(!PlaceDraft(name: "T", cityName: "Lisbon").isReady)
    #expect(!PlaceDraft(name: "Tasca", cityName: "  ").isReady)
    #expect(PlaceDraft(name: "Tasca", cityName: "Lisbon").isReady)
  }

  @Test func clearsNameAndKindButKeepsTheCity() {
    var draft = PlaceDraft(name: "Tasca", cityName: "Lisbon", category: "bar")
    let id = draft.submissionID
    draft.clearAfterSubmit()
    #expect(draft.name.isEmpty)
    #expect(draft.category.isEmpty)
    #expect(draft.cityName == "Lisbon")
    #expect(draft.submissionID != id)
  }

  @Test func clampsToTheServerLimits() {
    let draft = PlaceDraft(name: String(repeating: "a", count: 400), cityName: String(repeating: "b", count: 300))
    #expect(draft.name.count == PlaceDraft.nameLimit)
    #expect(draft.cityName.count == PlaceDraft.cityLimit)
  }
}

/// The stores against the offline service.
@MainActor struct ContributeStoreTests {
  @Test func claimFormFilesEveryAnswerAndShowsTheResult() async {
    let task = VerificationTask(poiID: "5f0c0000-0000-4000-8000-000000000001", poiName: "Café", requestedFields: [.dietary, .vibe])
    let store = ClaimFormStore(task: task, service: PreviewContributeService(claimStatus: .accepted))
    #expect(store.field == .dietary)
    #expect(!store.isReady)
    store.toggle("vegan")
    store.toggle("gluten_free")
    #expect(store.claimValues == ["gluten_free", "vegan"])
    await store.submit()
    #expect(store.result?.status == .accepted)
    #expect(store.tokens.isEmpty)
  }

  @Test func switchingFieldClearsAnswersAndResult() async {
    let task = VerificationTask(poiID: "p", poiName: "Café", requestedFields: [.crowdLevel, .openingHours])
    let store = ClaimFormStore(task: task, service: PreviewContributeService())
    store.toggle("busy")
    await store.submit()
    #expect(store.result != nil)
    store.select(.openingHours)
    #expect(store.result == nil)
    #expect(store.tokens.isEmpty)
    #expect(store.isReady)
    #expect(store.claimValues == ["mon-fri 09:00-17:00; sat-sun closed"])
  }

  @Test func aTaskWithNothingToAskHasNoField() {
    let store = ClaimFormStore(task: VerificationTask(poiID: "p", poiName: "Café", requestedFields: []), service: PreviewContributeService())
    #expect(store.field == nil)
    #expect(!store.isReady)
  }

  @Test func pageLoadsAndPages() async {
    let store = ContributeStore(service: PreviewContributeService())
    await store.load()
    #expect(store.phase == .loaded)
    #expect(store.tasks.count == 12)
    #expect(store.visibleTasks.count == 5)
    #expect(store.pageCount == 3)
    store.goToPage(9)
    #expect(store.page == 3)
    #expect(store.visibleTasks.count == 2)
    #expect(store.profile.badges == ["local-scout"])
  }

  @Test func failedTasksFailThePage() async {
    let store = ContributeStore(service: PreviewContributeService(failTasks: true))
    await store.load()
    guard case .failed(let message) = store.phase else {
      Issue.record("expected a failed page, got \(store.phase)")
      return
    }
    #expect(!message.isEmpty)
    #expect(store.tasks.isEmpty)
  }

  @Test func aConfirmedPlaceStaysWithItsOutcome() async throws {
    let store = ContributeStore(service: PreviewContributeService())
    await store.load()
    let place = try #require(store.shownPending.first)
    await store.confirm(place)
    #expect(store.outcome(for: place)?.promoted == true)
    #expect(store.shownPending.contains(place))
  }

  @Test func aSearchedPlaceOnTheGapListKeepsItsFields() async {
    let store = ContributeStore(service: PreviewContributeService())
    await store.load()
    var poi = Loci_Poi_POIDetailedInfo()
    poi.id = VerificationTask.previewTasks[1].poiID
    poi.name = VerificationTask.previewTasks[1].poiName
    #expect(store.task(for: poi).requestedFields == [.crowdLevel, .noiseLevel])
  }

  @Test func searchNeedsACityWithoutALocation() async {
    let store = ContributeStore(service: PreviewContributeService())
    store.query = "cafe"
    #expect(!store.canSearch)
    store.city = "Lisbon"
    #expect(store.canSearch)
    await store.search()
    #expect(store.results.count == 3)
    #expect(store.hasSearched)
  }

  @Test func addPlaceKeepsTheCityForTheNextOne() async {
    let store = AddPlaceStore(service: PreviewContributeService(), city: "Lisbon")
    store.name = "Tasca do Chico"
    let id = store.draft.submissionID
    await store.submit()
    #expect(store.result?.submissionID == id)
    #expect(store.name.isEmpty)
    #expect(store.cityName == "Lisbon")
  }
}
