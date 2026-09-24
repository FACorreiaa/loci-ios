import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Pack fixtures shaped the way the server sends them.
enum PackFixture {
  static func stop(_ name: String, _ lat: Double? = nil, _ lon: Double? = nil, id: String? = nil, poiID: String = "", minutes: Int32? = nil)
    -> Loci_Trip_TripStop
  {
    var stop = Loci_Trip_TripStop()
    stop.id = id ?? name
    stop.name = name
    stop.poiID = poiID
    if let minutes { stop.durationMinutes = minutes }
    if let lat, let lon {
      stop.poi.latitude = lat
      stop.poi.longitude = lon
      stop.poi.category = "museum"
    }
    return stop
  }

  static func day(_ number: Int32, _ stops: [Loci_Trip_TripStop], title: String = "") -> Loci_Bundle_V1_BundleDay {
    var day = Loci_Bundle_V1_BundleDay()
    day.dayNumber = number
    day.title = title
    day.stops = stops
    return day
  }
}

/// Mirrors web's `lib/bundles/points.test.ts`.
struct PackPointsTests {
  typealias Fix = PackFixture

  @Test func convertsTheServersOneBasedDayToZeroBased() {
    // Passing the server's number straight through renders a three-day pack as
    // Day 2 to Day 4, with no Day 1 at all.
    let points = PackPoints.from([Fix.day(1, [Fix.stop("a", 38.7, -9.1)])])
    #expect(points.first?.day == 0)
  }

  @Test func skipsAStopWithNoPositionRatherThanPlacingItAtZeroZero() {
    let points = PackPoints.from([Fix.day(1, [Fix.stop("placed", 38.7, -9.1), Fix.stop("unplaced")])])
    #expect(points.count == 1)
    #expect(points.first?.name == "placed")
  }

  @Test func numbersStopsAcrossTheWholePackNotPerDay() {
    let points = PackPoints.from([Fix.day(1, [Fix.stop("a", 1, 1), Fix.stop("b", 2, 2)]), Fix.day(2, [Fix.stop("c", 3, 3)])])
    #expect(points.map(\.seq) == [1, 2, 3])
    #expect(points.map(\.day) == [0, 0, 1])
  }

  @Test func keepsNumberingContiguousWhenAPositionlessStopIsSkipped() {
    let points = PackPoints.from([Fix.day(1, [Fix.stop("a", 1, 1), Fix.stop("skipped"), Fix.stop("c", 3, 3)])])
    #expect(points.map(\.seq) == [1, 2])
  }

  @Test func returnsNothingWhenNoStopHasAPosition() { #expect(PackPoints.from([Fix.day(1, [Fix.stop("nowhere")])]).isEmpty) }

  @Test func fallsBackToAComposedIdWhenAStopHasNone() {
    let points = PackPoints.from([Fix.day(2, [Fix.stop("x", 1, 2, id: "")])])
    #expect(points.first?.id == "2-0")
  }

  @Test func carriesNameCategoryAndPosition() throws {
    let point = try #require(PackPoints.from([Fix.day(1, [Fix.stop("Sé", 38.7098, -9.1334)])]).first)
    #expect(point.name == "Sé")
    #expect(point.category == "museum")
    #expect(point.latitude == 38.7098)
    #expect(point.longitude == -9.1334)
  }
}

/// Mirrors web's `lib/bundles/themes.test.ts` (without `priceLabel`: iOS shows no prices).
struct PackThemesTests {
  @Test func everyThemeHasALabelAndAnEmoji() {
    for theme in PackTheme.allCases {
      #expect(!theme.label.isEmpty)
      #expect(!theme.emoji.isEmpty)
    }
  }

  /// The catalog filters on these exact ids; they must match the server's seeds.
  @Test func vocabularyMatchesTheServer() {
    #expect(PackTheme.allCases.map(\.rawValue) == ["food", "art", "outdoors", "architecture", "nightlife", "family", "local_life"])
  }

  @Test func fallsBackToTheRawIdRatherThanBlank() {
    #expect(PackTheme.label(for: "not_a_theme") == "not_a_theme")
    #expect(PackTheme.label(for: "food") == "Food & wine")
    #expect(PackTheme.label(for: "local_life") == "Local life")
  }

  @Test func collapsesARunIntoARange() { #expect(PackMonths.label([3, 4, 5]) == "Mar–May") }

  @Test func keepsASingleMonthAsItself() { #expect(PackMonths.label([2]) == "Feb") }

  // Most winter packs are tagged Nov, Dec, Jan, Feb. Sorted naively that reads
  // "Jan–Feb, Nov–Dec", which describes two seasons instead of one.
  @Test func readsAWinterThatWrapsTheYearEndAsOneRange() { #expect(PackMonths.label([1, 2, 11, 12]) == "Nov–Feb") }

  @Test func handlesTheEmptyAndFullCases() {
    #expect(PackMonths.label([]) == "Any time")
    #expect(PackMonths.label(Array(1...12)) == "All year")
  }

  @Test func ignoresValuesThatAreNotMonths() { #expect(PackMonths.label([0, 13, 6]) == "Jun") }

  @Test func separatesRunsThatAreNotAdjacent() {
    #expect(PackMonths.label([3, 4, 9, 10, 6, 6]) == "Mar–Apr, Jun, Sep–Oct")
    #expect(PackMonths.label([12, 1, 6]) == "Dec–Jan, Jun")
  }

  @Test func upcomingMonthsWrapPastDecember() {
    #expect(PackMonths.upcoming(from: 9) == [9, 10, 11])
    #expect(PackMonths.upcoming(from: 11) == [11, 12, 1])
    #expect(PackMonths.upcoming(from: 12) == [12, 1, 2])
  }
}

/// Web's `toDetail` (lib/api/bundles.ts) and the pieces iOS builds on it.
/// Main actor: `ResultsMapData` is app-isolated.
@MainActor struct PackDetailMappingTests {
  typealias Fix = PackFixture

  private func detail(locked: Int32 = 0, paid: Bool = false, owned: Bool = false, days: [Loci_Bundle_V1_BundleDay]) -> Loci_Bundle_V1_BundleDetail {
    var detail = Loci_Bundle_V1_BundleDetail()
    detail.bundle.id = "b1"
    detail.bundle.slug = "lisbon"
    detail.bundle.title = "Lisbon"
    detail.bundle.months = [4, 5]
    detail.bundle.isPaid = paid
    detail.bundle.owned = owned
    detail.days = days
    detail.lockedDayCount = locked
    return detail
  }

  @Test func stopDayIsDayNumberMinusOne() {
    let mapped = PackDetail(detail(days: [Fix.day(1, [Fix.stop("a")]), Fix.day(3, [Fix.stop("b")])]))
    #expect(mapped.days.map(\.dayNumber) == [1, 3])
    #expect(mapped.stops.map(\.day) == [0, 2])
  }

  @Test func stopFieldsMapLikeWeb() throws {
    let stops = [Fix.stop("x", 1, 2, id: "", poiID: "", minutes: 90), Fix.stop("y", id: "s2", poiID: "11111111-1111-4111-8111-111111111111")]
    let mapped = PackDetail(detail(days: [Fix.day(2, stops, title: "Old town")]))
    let day = try #require(mapped.days.first)
    #expect(day.title == "Old town")
    #expect(day.stops[0].key == "2-0")
    #expect(day.stops[0].placeId == nil)
    #expect(day.stops[0].timeToSpend == "90 min")
    #expect(day.stops[1].key == "s2")
    #expect(day.stops[1].placeId == "11111111-1111-4111-8111-111111111111")
    #expect(day.stops[1].timeToSpend == nil)
  }

  @Test func zeroMinutesIsNoTimeToSpend() {
    let mapped = PackDetail(detail(days: [Fix.day(1, [Fix.stop("a", minutes: 0)])]))
    #expect(mapped.stops.first?.timeToSpend == nil)
  }

  @Test func blurbIsTheAuthorsNotes() {
    var stop = Fix.stop("a", 1, 1)
    stop.notes = "Go early."
    let mapped = PackDetail(detail(days: [Fix.day(1, [stop])]))
    #expect(mapped.stops.first?.blurb == "Go early.")
    #expect(mapped.stops.first?.card.blurb == "Go early.")
  }

  @Test func accessFollowsLockedDayCount() {
    #expect(PackDetail(detail(days: [])).access == .unlocked)
    #expect(PackDetail(detail(locked: 2, paid: true, days: [])).access == .locked(days: 2))
  }

  @Test func countsStopsTheMapCannotShow() {
    let mapped = PackDetail(detail(days: [Fix.day(1, [Fix.stop("a", 1, 1), Fix.stop("b")]), Fix.day(2, [Fix.stop("c")])]))
    #expect(mapped.points.count == 1)
    #expect(mapped.unplacedCount == 2)
  }

  @Test func groupsUseTheServersDayAndMapPinsMatchCardNumbers() {
    let mapped = PackDetail(detail(days: [Fix.day(1, [Fix.stop("a"), Fix.stop("b", 1, 1)]), Fix.day(2, [Fix.stop("c", 2, 2)])]))
    let groups = mapped.groups
    #expect(groups.map(\.number) == [1, 2])
    let sequence = DayGrouping.sequence(groups)
    // Card "b" is the second stop even though "a" has no position.
    #expect(sequence[groups[0].stops[1].stableID] == 2)
    let map = ResultsMapData(groups: groups, extras: [], sequence: sequence, showsDays: true, alerts: [])
    #expect(map.pins.map(\.index) == [2, 3])
    #expect(map.pins.map(\.day) == [1, 2])
  }

  @Test func cardsKeyOnTheRealPlaceAndStayUniqueForARepeatVisit() {
    let poi = "22222222-2222-4222-8222-222222222222"
    let mapped = PackDetail(
      detail(days: [Fix.day(1, [Fix.stop("Sé", 1, 1, id: "s1", poiID: poi)]), Fix.day(2, [Fix.stop("Sé", 1, 1, id: "s2", poiID: poi)])])
    )
    let cards = mapped.stops.map(\.card)
    #expect(cards[0].id == poi)
    #expect(cards[1].id == "s2")
    #expect(Set(cards.map(\.stableID)).count == 2)
    // The detail sheet always gets the real place, even for the repeat.
    #expect(mapped.stops[1].detailPlace.id == poi)
  }

  @Test func aStopWithoutAPlaceIsNotKeyedByTheStopId() {
    let mapped = PackDetail(detail(days: [Fix.day(1, [Fix.stop("Somewhere", id: "33333333-3333-4333-8333-333333333333")])]))
    // A stop id is a UUID too; used as a POI id it would save the wrong place.
    #expect(mapped.stops.first?.card.id.isEmpty == true)
    #expect(mapped.stops.first?.detailPlace.id.isEmpty == true)
  }
}

/// PackCard's badge and the catalog request.
struct PackCatalogTests {
  private func pack(paid: Bool, owned: Bool) -> PackSummary {
    PackSummary(id: "b", slug: "s", title: "t", cityName: "c", theme: "food", dayCount: 1, stopCount: 1, isPaid: paid, owned: owned)
  }

  @Test func badgeIsFreeYoursOrLocked() {
    #expect(pack(paid: false, owned: false).badge == .free)
    // The server reports a free pack as owned; it still reads Free.
    #expect(pack(paid: false, owned: true).badge == .free)
    #expect(pack(paid: true, owned: true).badge == .yours)
    #expect(pack(paid: true, owned: false).badge == .locked)
  }

  @Test func sizeLabelPluralises() {
    #expect(pack(paid: false, owned: false).sizeLabel == "1 day · 1 stop")
    var big = pack(paid: false, owned: false)
    big.dayCount = 3
    big.stopCount = 12
    #expect(big.sizeLabel == "3 days · 12 stops")
  }

  @Test func unsetFiltersAreNotSent() {
    let request = PackFilters().request
    #expect(!request.hasTheme)
    #expect(!request.hasMonth)
    #expect(!request.hasOnlyFree)
    #expect(!request.hasCityName)
    #expect(request.pagination.page == 1)
    #expect(request.pagination.pageSize == 24)
  }

  @Test func setFiltersAreSent() {
    let request = PackFilters(theme: .localLife, month: 12, onlyFree: true).request
    #expect(request.theme == "local_life")
    #expect(request.month == 12)
    #expect(request.hasOnlyFree && request.onlyFree)
    #expect(PackFilters(month: 13).request.hasMonth == false)
  }

  @Test func summaryMapsFromTheProto() {
    var bundle = Loci_Bundle_V1_Bundle()
    bundle.id = "b1"
    bundle.slug = "porto"
    bundle.title = "Porto"
    bundle.cityName = "Porto"
    bundle.theme = "food"
    bundle.months = [11, 12]
    bundle.dayCount = 3
    bundle.stopCount = 11
    bundle.isPaid = true
    bundle.priceCents = 499
    let summary = PackSummary(bundle)
    #expect(summary.months == [11, 12])
    #expect(summary.dayCount == 3)
    #expect(summary.badge == .locked)
  }
}
