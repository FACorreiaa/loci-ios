import Connect
import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

private let gb = Locale(identifier: "en_GB")
private var lisbon: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Europe/Lisbon") ?? .gmt
  return calendar
}

private func day(_ y: Int, _ m: Int, _ d: Int, calendar: Calendar = lisbon) -> Date {
  calendar.date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
}

private func tripDay(utc y: Int, _ m: Int, _ d: Int) -> Loci_Trip_TripDay {
  var utc = Calendar(identifier: .gregorian)
  utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
  var day = Loci_Trip_TripDay()
  day.date = Google_Protobuf_Timestamp(date: utc.date(from: DateComponents(year: y, month: m, day: d)) ?? Date())
  return day
}

/// web: lib/trip-format.test.ts
struct TripFormatTests {
  @Test func eyebrowPluralises() {
    #expect(TripFormat.heroEyebrow(dayCount: 1) == "Route · 1 day")
    #expect(TripFormat.heroEyebrow(dayCount: 3) == "Route · 3 days")
  }

  @Test func noDatesIsNil() {
    #expect(TripFormat.tripDates([Date]()) == nil)
    #expect(TripFormat.tripDates([Loci_Trip_TripDay(), Loci_Trip_TripDay()]) == nil)
  }

  @Test func singleDateCollapses() {
    #expect(TripFormat.tripDates([day(2026, 10, 4)], calendar: lisbon, locale: gb) == "4 Oct")
    #expect(TripFormat.tripDates([day(2026, 10, 4), day(2026, 10, 4)], calendar: lisbon, locale: gb) == "4 Oct")
  }

  @Test func sameMonthSharesTheMonth() {
    #expect(TripFormat.tripDates([day(2026, 10, 6), day(2026, 10, 4)], calendar: lisbon, locale: gb) == "4–6 Oct")
  }

  @Test func crossMonthNamesBoth() {
    #expect(TripFormat.tripDates([day(2026, 9, 30), day(2026, 10, 2)], calendar: lisbon, locale: gb) == "30 Sep – 2 Oct")
  }

  /// A day stored as midnight UTC must keep its calendar day west of Greenwich.
  @Test func utcMidnightKeepsItsDayInNewYork() {
    var newYork = Calendar(identifier: .gregorian)
    newYork.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
    let days = [tripDay(utc: 2026, 10, 4), tripDay(utc: 2026, 10, 6)]
    #expect(TripFormat.tripDates(days, calendar: newYork, locale: gb) == "4–6 Oct")
  }

  /// The app's Calendar pin used to write local midnight, which east of UTC is
  /// the previous evening in UTC; the hero and the day headers read it through
  /// DayTimeline.localMidnight like the Today band, so it keeps its day too.
  @Test func localMidnightEastOfUTCKeepsItsDay() throws {
    var athens = Calendar(identifier: .gregorian)
    athens.timeZone = TimeZone(identifier: "Europe/Athens") ?? .gmt
    var day = Loci_Trip_TripDay()
    day.date = Google_Protobuf_Timestamp(date: try #require(athens.date(from: DateComponents(year: 2026, month: 10, day: 4))))
    #expect(TripFormat.tripDates([day], calendar: athens, locale: gb) == "4 Oct")
  }

  @Test func minutesRoundTrip() {
    #expect(TripFormat.minutesToHHMM(570) == "09:30")
    #expect(TripFormat.minutesToHHMM(nil).isEmpty)
    #expect(TripFormat.hhmmToMinutes("09:30") == 570)
    #expect(TripFormat.hhmmToMinutes("") == nil)
    #expect(TripFormat.hhmmToMinutes("ab:cd") == nil)
    let date = TripFormat.date(fromMinutes: 1215, on: day(2026, 10, 4), calendar: lisbon)
    #expect(TripFormat.minutes(of: date, calendar: lisbon) == 1215)
  }

  @Test func labelsMatchWeb() {
    #expect(TripFormat.paceLabel(.relaxed) == "Relaxed")
    #expect(TripFormat.paceLabel(.unspecified) == "—")
    #expect(TripFormat.budgetLabel(1) == "€")
    #expect(TripFormat.budgetLabel(4) == "€€€€")
    #expect(TripFormat.budgetLabel(5) == nil)
  }

  @Test func badgesStateEveryValue() {
    var constraints = Loci_Trip_TripConstraint()
    constraints.pace = .packed
    #expect(TripFormat.preferenceBadges(constraints) == ["Packed"])
    constraints.budgetLevel = 3
    constraints.mobility = "transit"
    constraints.dayEndMinute = 1080
    #expect(TripFormat.preferenceBadges(constraints) == ["Packed", "€€€", "transit", "—–18:00"])
  }

  @Test func secondTapClearsTheBudget() {
    #expect(TripFormat.toggledBudget(current: 2, tapped: 2) == nil)
    #expect(TripFormat.toggledBudget(current: 2, tapped: 3) == 3)
    #expect(TripFormat.toggledBudget(current: nil, tapped: 1) == 1)
  }

  /// Mobility has min_len 1 on the wire: empty clears the field instead of sending "".
  @Test func mergeClearsEmptyOptionals() {
    var constraints = Loci_Trip_TripConstraint()
    constraints.pace = .relaxed
    constraints.mobility = "walking"
    constraints.budgetLevel = 2
    constraints.dayStartMinute = 540
    var next = TripFormat.merged(constraints, with: .mobility("   "))
    #expect(!next.hasMobility)
    #expect(next.pace == .relaxed && next.budgetLevel == 2)
    next = TripFormat.merged(next, with: .budget(nil))
    #expect(!next.hasBudgetLevel)
    next = TripFormat.merged(next, with: .dayStart(nil))
    #expect(!next.hasDayStartMinute)
    next = TripFormat.merged(next, with: .dayEnd(1200))
    #expect(next.dayEndMinute == 1200)
    next = TripFormat.merged(next, with: .mobility(" wheelchair "))
    #expect(next.mobility == "wheelchair")
  }
}

/// web: components/trip/TripExportMenu.tsx
struct TripExportGateTests {
  /// Plan gating is off (PlanGating.enabled) until there are users to gate:
  /// every format exports for every plan, with no notice.
  @Test func nothingIsGatedByDefault() {
    #expect(!PlanGating.enabled)
    for format in TripExportGate.formats {
      #expect(TripExportGate.decide(format, isPro: false, dayCount: 5) == .export(notice: nil))
      #expect(!TripExportGate.isLocked(format, isPro: false, dayCount: 5))
    }
  }

  @Test func icsAlwaysExportsWhenGated() {
    #expect(TripExportGate.decide(.ics, isPro: true, dayCount: 3, gating: true) == .export(notice: nil))
    #expect(TripExportGate.decide(.ics, isPro: false, dayCount: 1, gating: true) == .export(notice: nil))
    guard case .export(let notice?) = TripExportGate.decide(.ics, isPro: false, dayCount: 3, gating: true) else {
      Issue.record("gated free multi-day ICS should export with a notice")
      return
    }
    #expect(notice.hasPrefix("Day-1 calendar works free"))
  }

  @Test func pdfIsProPastOneDayWhenGated() {
    #expect(TripExportGate.decide(.pdf, isPro: false, dayCount: 1, gating: true) == .export(notice: nil))
    #expect(TripExportGate.isLocked(.pdf, isPro: false, dayCount: 2, gating: true))
    #expect(!TripExportGate.isLocked(.pdf, isPro: true, dayCount: 5, gating: true))
  }

  @Test func markdownIsProOnlyWhenGated() {
    #expect(TripExportGate.isLocked(.markdown, isPro: false, dayCount: 1, gating: true))
    #expect(!TripExportGate.isLocked(.markdown, isPro: true, dayCount: 1, gating: true))
  }

  /// No pricing link and no price in any gate copy (App Store 3.1.1).
  @Test func copyNeverSellsOrLinks() {
    for format in TripExportGate.formats {
      for isPro in [false, true] {
        for dayCount in [1, 3] {
          let text: String? =
            switch TripExportGate.decide(format, isPro: isPro, dayCount: dayCount, gating: true) {
            case .export(let notice): notice
            case .locked(let message): message
            }
          guard let text else { continue }
          #expect(!text.contains("http") && !text.contains("pricing") && !text.contains("$") && !text.lowercased().contains("upgrade"))
        }
      }
    }
  }

  @Test func analyticsNamesMatchWeb() {
    #expect(TripExportGate.formats.map(TripExportGate.analyticsName) == ["ics", "pdf", "markdown"])
  }

  @Test func filenameStaysInTheTempFolder() {
    #expect(TripExportGate.filename(serverName: "lisbon.pdf", format: .pdf) == "lisbon.pdf")
    #expect(TripExportGate.filename(serverName: "", format: .markdown) == "trip.md")
    #expect(TripExportGate.filename(serverName: "../../etc/x.ics", format: .ics) == "x.ics")
    #expect(TripExportGate.filename(serverName: "..", format: .ics) == "trip.ics")
  }
}

private func item(_ kind: Loci_Trip_ChecklistItemKind, _ text: String, position: Int32 = 0, done: Bool = false, amount: Int64 = 0, currency: String = "") -> Loci_Trip_ChecklistItem {
  var item = Loci_Trip_ChecklistItem()
  item.id = UUID().uuidString.lowercased()
  item.kind = kind
  item.text = text
  item.position = position
  item.done = done
  item.amountMinor = amount
  item.currency = currency
  return item
}

private func suggestion(_ text: String) -> Loci_Trip_PackingSuggestion {
  var suggestion = Loci_Trip_PackingSuggestion()
  suggestion.text = text
  return suggestion
}

/// web: TripChecklists.tsx openSuggestions and the list maths.
struct TripChecklistTests {
  @Test func openSuggestionsHidePackedAndDismissedCaseInsensitively() {
    let open = TripChecklist.openSuggestions(
      [suggestion("Passport"), suggestion("Umbrella"), suggestion("Light jacket"), suggestion("Sunscreen")],
      items: [item(.packing, "passport"), item(.expense, "Sunscreen")],
      dismissed: ["  UMBRELLA "]
    )
    // An expense named "Sunscreen" does not count as packed.
    #expect(open.map(\.text) == ["Light jacket", "Sunscreen"])
  }

  @Test func openSuggestionsDropDuplicates() {
    let open = TripChecklist.openSuggestions([suggestion("Hat"), suggestion("hat "), suggestion("")], items: [], dismissed: [])
    #expect(open.map(\.text) == ["Hat"])
  }

  @Test func packedSummaryCountsPackingOnly() {
    #expect(TripChecklist.packedSummary([]) == nil)
    let items = [item(.packing, "a", done: true), item(.packing, "b"), item(.expense, "c", done: true)]
    #expect(TripChecklist.packedSummary(items) == "1/2 packed")
  }

  @Test func orderAndNextPosition() {
    let items = [item(.packing, "b", position: 2), item(.packing, "a", position: 0), item(.expense, "x", position: 9)]
    #expect(TripChecklist.items(items, kind: .packing).map(\.text) == ["a", "b"])
    #expect(TripChecklist.nextPosition(items, kind: .packing) == 3)
    #expect(TripChecklist.nextPosition([], kind: .expense) == 0)
  }

  @Test func makeItemTrimsCapsAndRejectsEmpty() {
    #expect(TripChecklist.makeItem(kind: .packing, text: "   ", position: 0) == nil)
    let long = TripChecklist.makeItem(kind: .packing, text: String(repeating: "x", count: 400), position: 0)
    #expect(long?.text.count == 300)
    let expense = TripChecklist.makeItem(kind: .expense, text: " Taxi ", position: 1, amountMinor: 1250, currency: "EUR")
    #expect(expense?.text == "Taxi" && expense?.amountMinor == 1250 && expense?.currency == "EUR")
    // A client UUID, lowercased, which the server's uuid rule accepts.
    #expect(expense.map { UUID(uuidString: $0.id) != nil && $0.id == $0.id.lowercased() } == true)
    // Packing items carry no money.
    #expect(TripChecklist.makeItem(kind: .packing, text: "Hat", position: 0, amountMinor: 5, currency: "EUR")?.currency.isEmpty == true)
  }

  @Test func amountsParseEitherDecimalMark() {
    #expect(TripChecklist.amountMinor(from: "12.50", currency: "EUR") == 1250)
    #expect(TripChecklist.amountMinor(from: "12,5", currency: "EUR") == 1250)
    #expect(TripChecklist.amountMinor(from: "1.234,56", currency: "EUR") == 123_456)
    #expect(TripChecklist.amountMinor(from: "1,234.56", currency: "USD") == 123_456)
    #expect(TripChecklist.amountMinor(from: "1500", currency: "JPY") == 1500)
    #expect(TripChecklist.amountMinor(from: "0.005", currency: "EUR") == 1)
    #expect(TripChecklist.amountMinor(from: "-3", currency: "EUR") == nil)
    #expect(TripChecklist.amountMinor(from: "abc", currency: "EUR") == nil)
    #expect(TripChecklist.amountMinor(from: "", currency: "EUR") == nil)
  }

  @Test func currencyDefaultsToTheOneInUse() {
    #expect(TripChecklist.defaultCurrency([item(.expense, "x", currency: "GBP")], locale: Locale(identifier: "pt_PT")) == "GBP")
    #expect(TripChecklist.defaultCurrency([], locale: Locale(identifier: "pt_PT")) == "EUR")
    #expect(TripChecklist.defaultCurrency([], locale: Locale(identifier: "en_US")) == "USD")
  }

  @Test func totalsNeverMixCurrencies() {
    let items = [
      item(.expense, "a", amount: 1000, currency: "EUR"),
      item(.expense, "b", position: 1, amount: 250, currency: ""),
      item(.expense, "c", position: 2, amount: 300, currency: "GBP"),
      item(.packing, "d", amount: 99),
    ]
    let totals = TripChecklist.totals(items, fallbackCurrency: "EUR")
    #expect(totals.map(\.currency) == ["EUR", "GBP"])
    #expect(totals.map(\.amountMinor) == [1250, 300])
    let label = TripChecklist.totalLabel(items, fallbackCurrency: "EUR", locale: Locale(identifier: "en_GB"))
    #expect(label == "€12.50 + £3.00")
  }
}

// MARK: - Store

private actor FakeLog {
  var calls: [String] = []

  func add(_ call: String) { calls.append(call) }
}

private struct FakeChecklistService: TripChecklistService {
  var checklistResult: Result<Loci_Trip_GetTripChecklistResponse, TripRPCError> = .success(.init())
  var failWrites: TripRPCError?
  let log = FakeLog()

  func checklist(tripID: String) async throws(TripRPCError) -> Loci_Trip_GetTripChecklistResponse { try checklistResult.get() }
  func suggestions(tripID: String) async throws(TripRPCError) -> Loci_Trip_SuggestPackingResponse {
    var response = Loci_Trip_SuggestPackingResponse()
    response.suggestions = [suggestion("Passport"), suggestion("Hat")]
    return response
  }
  func upsert(tripID: String, item: Loci_Trip_ChecklistItem) async throws(TripRPCError) -> Loci_Trip_ChecklistItem {
    await log.add("upsert \(item.text)")
    if let failWrites { throw failWrites }
    var saved = item
    saved.updatedAt = Google_Protobuf_Timestamp(date: Date(timeIntervalSince1970: 1))
    return saved
  }
  func delete(tripID: String, itemID: String) async throws(TripRPCError) {
    await log.add("delete")
    if let failWrites { throw failWrites }
  }
  func dismiss(tripID: String, text: String) async throws(TripRPCError) {
    await log.add("dismiss \(text)")
    if let failWrites { throw failWrites }
  }
}

@MainActor struct TripChecklistStoreTests {
  private let broken = TripRPCError(code: .internalError, message: "boom")

  @Test func loadsItemsAndSuggestions() async {
    var response = Loci_Trip_GetTripChecklistResponse()
    response.items = [item(.packing, "passport")]
    response.dismissedSuggestions = []
    let store = TripChecklistStore(tripID: "t", service: FakeChecklistService(checklistResult: .success(response)))
    await store.load()
    #expect(store.availability == .ready)
    #expect(store.openSuggestions.map(\.text) == ["Hat"])
  }

  /// Before the server deploy the RPCs are Unimplemented: hide editing, no alert.
  @Test func unimplementedIsQuiet() async {
    let store = TripChecklistStore(
      tripID: "t",
      service: FakeChecklistService(checklistResult: .failure(TripRPCError(code: .unimplemented, message: "nope")))
    )
    await store.load()
    #expect(store.availability == .unavailable)
    #expect(store.error == nil)
    #expect(!store.canEdit)
  }

  @Test func addAdoptsTheServerCopy() async {
    let store = TripChecklistStore(tripID: "t", service: FakeChecklistService(), availability: .ready)
    await store.addPacking("  Hat ")
    #expect(store.packing.map(\.text) == ["Hat"])
    #expect(store.packing.first?.hasUpdatedAt == true)
  }

  @Test func failedAddRollsBack() async {
    let store = TripChecklistStore(tripID: "t", service: FakeChecklistService(failWrites: broken), availability: .ready)
    await store.addPacking("Hat")
    #expect(store.items.isEmpty)
    #expect(store.error == "boom")
  }

  @Test func failedToggleRestoresThePreviousValue() async {
    let hat = item(.packing, "Hat")
    let store = TripChecklistStore(tripID: "t", service: FakeChecklistService(failWrites: broken), items: [hat], availability: .ready)
    await store.toggle(hat)
    #expect(store.items == [hat])
  }

  @Test func failedDeletePutsItBackInPlace() async {
    let a = item(.packing, "a", position: 0)
    let b = item(.packing, "b", position: 1)
    let store = TripChecklistStore(tripID: "t", service: FakeChecklistService(failWrites: broken), items: [a, b], availability: .ready)
    await store.delete(a)
    #expect(store.items.map(\.text) == ["a", "b"])
  }

  @Test func failedDismissShowsTheSuggestionAgain() async {
    let store = TripChecklistStore(
      tripID: "t",
      service: FakeChecklistService(failWrites: broken),
      suggestions: [suggestion("Hat")],
      availability: .ready
    )
    await store.dismiss(suggestion("Hat"))
    #expect(store.openSuggestions.map(\.text) == ["Hat"])
  }

  @Test func dismissHidesIt() async {
    let store = TripChecklistStore(tripID: "t", service: FakeChecklistService(), suggestions: [suggestion("Hat")], availability: .ready)
    await store.dismiss(suggestion("Hat"))
    #expect(store.openSuggestions.isEmpty)
    #expect(store.dismissed == ["hat"])
  }

  @Test func addAllTakesEveryOpenSuggestionInOrder() async {
    let store = TripChecklistStore(
      tripID: "t",
      service: FakeChecklistService(),
      items: [item(.packing, "hat")],
      suggestions: [suggestion("Hat"), suggestion("Passport"), suggestion("Charger")],
      availability: .ready
    )
    await store.acceptAll()
    #expect(store.packing.map(\.text) == ["hat", "Passport", "Charger"])
    #expect(store.openSuggestions.isEmpty)
  }

  @Test func expenseUsesMinorUnitsAndRejectsNonNumbers() async {
    let store = TripChecklistStore(tripID: "t", service: FakeChecklistService(), availability: .ready, locale: Locale(identifier: "pt_PT"))
    #expect(await store.addExpense(label: "Taxi", amount: "12,40"))
    #expect(!(await store.addExpense(label: "Lunch", amount: "twelve")))
    #expect(store.expenses.map(\.amountMinor) == [1240])
    #expect(store.expenses.first?.currency == "EUR")
  }

  @Test func nothingIsSentWhileUnavailable() async {
    let service = FakeChecklistService()
    let store = TripChecklistStore(tripID: "t", service: service, availability: .unavailable)
    await store.addPacking("Hat")
    #expect(store.items.isEmpty)
    #expect(await service.log.calls.isEmpty)
  }

  // MARK: - Review follow-ups (#31)

  private func freshCache() -> LocalCache {
    LocalCache(root: FileManager.default.temporaryDirectory.appending(path: "loci-checklist-\(UUID().uuidString)"))
  }

  /// A load that fails for any reason but Unimplemented is a failure with a
  /// Retry, not "checklists are not available on your account".
  @Test func failedLoadCanBeRetried() async {
    let store = TripChecklistStore(tripID: "t", service: FakeChecklistService(checklistResult: .failure(broken)), cache: freshCache())
    await store.load()
    #expect(store.availability == .failed("boom"))
    #expect(store.error == nil)
    #expect(!store.canEdit)
  }

  @Test func cachedCopyShowsReadOnlyWhenTheServerIsUnreachable() async throws {
    let cache = freshCache()
    var response = Loci_Trip_GetTripChecklistResponse()
    response.items = [item(.packing, "passport")]
    try await cache.put(response, kind: .checklist, id: "t")
    let store = TripChecklistStore(tripID: "t", service: FakeChecklistService(checklistResult: .failure(broken)), cache: cache)
    await store.load()
    #expect(store.packing.map(\.text) == ["passport"])
    #expect(store.availability == .cached)
    #expect(!store.canEdit)
    #expect(store.error == nil)
  }

  @Test func aSuccessfulLoadIsKeptForNextTime() async throws {
    let cache = freshCache()
    var response = Loci_Trip_GetTripChecklistResponse()
    response.items = [item(.packing, "passport")]
    let store = TripChecklistStore(tripID: "t", service: FakeChecklistService(checklistResult: .success(response)), cache: cache)
    await store.load()
    let copy = await cache.get(Loci_Trip_GetTripChecklistResponse.self, kind: .checklist, id: "t")
    #expect(copy?.value.items.map(\.text) == ["passport"])
  }

  /// Toggle A is sent, toggle B on the same item lands, then A fails: A's
  /// rollback must not undo B.
  @Test func aFailedEditNeverUndoesALaterOne() {
    let failed = item(.packing, "hat", done: true)
    var later = failed
    later.done = false
    #expect(TripChecklist.shouldRollBack(current: failed, failed: failed))
    #expect(!TripChecklist.shouldRollBack(current: later, failed: failed))
    #expect(!TripChecklist.shouldRollBack(current: nil, failed: failed))
  }
}

struct TripRPCErrorTests {
  @Test func conflictAndUnimplementedCodes() {
    #expect(TripRPCError(code: .failedPrecondition, message: "").isVersionConflict)
    #expect(TripRPCError(code: .aborted, message: "").isVersionConflict)
    #expect(!TripRPCError(code: .internalError, message: "").isVersionConflict)
    #expect(TripRPCError(code: .unimplemented, message: "").isUnimplemented)
    #expect(TripRPCError(code: .canceled, message: "").isCancelled)
  }
}
