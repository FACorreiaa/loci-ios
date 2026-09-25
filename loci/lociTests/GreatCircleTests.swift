import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

/// The globe's pure helpers, ported from web's components/features/Map/geo.ts,
/// useArcPlayhead.ts `formatLegLabel` and lib/api/travel-history.ts
/// `trendPercent` (web has no tests for any of them). Number formatting is
/// pinned to a locale so the asserts do not depend on the machine.
struct GreatCircleTests {
  private let lisbon = GeoPoint(latitude: 38.7223, longitude: -9.1393)
  private let porto = GeoPoint(latitude: 41.1579, longitude: -8.6291)
  private let tokyo = GeoPoint(latitude: 35.6762, longitude: 139.6503)
  private let auckland = GeoPoint(latitude: -36.8485, longitude: 174.7633)
  private let santiago = GeoPoint(latitude: -33.4489, longitude: -70.6693)
  private let losAngeles = GeoPoint(latitude: 34.0522, longitude: -118.2437)

  private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

  @Test func segmentCountIsOnePerTwoDegreesClampedTo24Through128() {
    #expect(GreatCircle.segmentCount(degrees: 0.5) == 24)
    #expect(GreatCircle.segmentCount(degrees: 48) == 24)
    #expect(GreatCircle.segmentCount(degrees: 49) == 25)
    #expect(GreatCircle.segmentCount(degrees: 100) == 50)
    #expect(GreatCircle.segmentCount(degrees: 256) == 128)
    #expect(GreatCircle.segmentCount(degrees: 300) == 128)
  }

  @Test func pathRunsEndToEndWithOnePointPerSegmentPlusOne() {
    let path = GreatCircle.path(from: lisbon, to: tokyo)
    // Lisbon–Tokyo is ~100.2° of arc → 51 segments, 52 points.
    let degrees = GreatCircle.distanceKm(lisbon, tokyo) / GreatCircle.earthRadiusKm * 180 / .pi
    #expect(GreatCircle.segmentCount(degrees: degrees) == 51)
    #expect(path.count == 52)
    #expect(close(path[0].latitude, lisbon.latitude) && close(path[0].longitude, lisbon.longitude))
    let last = path[path.count - 1]
    #expect(close(last.latitude, tokyo.latitude) && close(last.longitude, tokyo.longitude))
  }

  @Test func pathLengthMatchesTheHaversineDistance() {
    let path = GreatCircle.path(from: lisbon, to: tokyo)
    let walked = zip(path, path.dropFirst()).reduce(0) { $0 + GreatCircle.distanceKm($1.0, $1.1) }
    let direct = GreatCircle.distanceKm(lisbon, tokyo)
    #expect(abs(walked - direct) < 1)
    // A geodesic, not the chord: the path bows north of both endpoints.
    #expect(path.map(\.latitude).max() ?? 0 > 60)
  }

  @Test func haversineMatchesKnownDistances() {
    #expect(abs(GreatCircle.distanceKm(lisbon, porto) - 274) < 3)
    #expect(abs(GreatCircle.distanceKm(lisbon, tokyo) - 11_140) < 60)
  }

  @Test func coincidentEndpointsComeBackAsIs() {
    #expect(GreatCircle.path(from: lisbon, to: lisbon) == [lisbon, lisbon])
    // Nothing to draw: a zero-length arc is no polyline at all.
    #expect(GreatCircle.segments([lisbon, lisbon]).isEmpty)
  }

  @Test func unwrappedPathNeverJumpsMoreThan180Degrees() {
    let path = GreatCircle.path(from: auckland, to: santiago)
    for (a, b) in zip(path, path.dropFirst()) { #expect(abs(b.longitude - a.longitude) <= 180) }
    // Auckland → Santiago goes east over the Pacific, so it ends past +180.
    #expect(close(path[path.count - 1].longitude, santiago.longitude + 360))
  }

  @Test func eastwardCrossingSplitsAtPlus180ThenMinus180() {
    let pieces = GreatCircle.segments(GreatCircle.path(from: auckland, to: santiago))
    #expect(pieces.count == 2)
    let first = pieces[0]
    let second = pieces[1]
    #expect(first.last?.longitude == 180)
    #expect(second.first?.longitude == -180)
    // The two sides meet at the same latitude: no gap.
    #expect(first.last?.latitude == second.first?.latitude)
    for piece in pieces {
      for point in piece { #expect((-180...180).contains(point.longitude)) }
      for (a, b) in zip(piece, piece.dropFirst()) { #expect(abs(b.longitude - a.longitude) < 180) }
    }
    #expect(close(first[0].longitude, auckland.longitude))
    #expect(close(second[second.count - 1].longitude, santiago.longitude))
  }

  @Test func westwardCrossingSplitsAtMinus180ThenPlus180() {
    let pieces = GreatCircle.segments(GreatCircle.path(from: losAngeles, to: tokyo))
    #expect(pieces.count == 2)
    #expect(pieces[0].last?.longitude == -180)
    #expect(pieces[1].first?.longitude == 180)
    #expect(close(pieces[1].last?.longitude ?? 0, tokyo.longitude))
  }

  @Test func aPathThatStaysOnOneSideIsOnePiece() {
    let path = GreatCircle.path(from: lisbon, to: tokyo)
    #expect(GreatCircle.segments(path) == [path])
  }

  @Test func aVertexExactlyOnTheSeamKeepsItsSide() {
    let path = [GeoPoint(latitude: 0, longitude: 179), GeoPoint(latitude: 1, longitude: 180), GeoPoint(latitude: 2, longitude: 181)]
    let pieces = GreatCircle.segments(path)
    #expect(pieces.count == 2)
    #expect(pieces[0] == [GeoPoint(latitude: 0, longitude: 179), GeoPoint(latitude: 1, longitude: 180)])
    #expect(pieces[1] == [GeoPoint(latitude: 1, longitude: -180), GeoPoint(latitude: 2, longitude: -179)])
  }

  @Test func centroidAveragesOnTheSphere() {
    let fiji = GeoPoint(latitude: 0, longitude: 179)
    let samoa = GeoPoint(latitude: 0, longitude: -179)
    let centre = GreatCircle.centroid([fiji, samoa])
    #expect(close(abs(centre?.longitude ?? 0), 180, 1e-6))
    #expect(GreatCircle.centroid([]) == nil)
  }

  @Test func midpointIsOnTheArc() {
    let mid = GreatCircle.midpoint(from: auckland, to: santiago)
    #expect((-180...180).contains(mid.longitude))
    #expect(abs(GreatCircle.distanceKm(auckland, mid) - GreatCircle.distanceKm(mid, santiago)) < 50)
  }
}

struct GlobeFormatTests {
  private let english = Locale(identifier: "en_US")

  @Test func trendIsNilWithoutAnEarlierFigure() {
    #expect(GlobeFormat.trendPercent(current: 5, previous: 0) == nil)
    #expect(GlobeFormat.trendPercent(current: 5, previous: -1) == nil)
    #expect(GlobeFormat.trendPercent(current: 0, previous: 0) == nil)
  }

  @Test func trendIsThePercentChange() {
    #expect(GlobeFormat.trendPercent(current: 12, previous: 10) == 20)
    #expect(GlobeFormat.trendPercent(current: 8, previous: 10) == -20)
    #expect(GlobeFormat.trendPercent(current: 10, previous: 10) == 0)
    #expect(GlobeFormat.trendPercent(current: 3, previous: 1) == 200)
  }

  @Test func trendTextRoundsLikeWeb() {
    #expect(GlobeFormat.trendText(19.5) == "+20%")
    #expect(GlobeFormat.trendText(-20) == "−20%")
    #expect(GlobeFormat.trendText(-0.4) == "0%")
    #expect(GlobeFormat.trendText(0) == "0%")
  }

  @Test func legLabelJoinsWhatIsKnown() {
    #expect(GlobeFormat.legLabel(mode: "fly", distanceKm: 1234.4, durationMins: 125, locale: english) == "fly · 1,234 km · 2h 5m")
    #expect(GlobeFormat.legLabel(mode: "rail", distanceKm: 999.6, durationMins: nil, locale: english) == "rail · 1,000 km")
    #expect(GlobeFormat.legLabel(mode: "drive", distanceKm: 0, durationMins: 45, locale: english) == "drive · 45m")
    #expect(GlobeFormat.legLabel(mode: "", distanceKm: 312, durationMins: 0, locale: english) == "312 km")
    #expect(GlobeFormat.legLabel(mode: "", distanceKm: 0, durationMins: nil, locale: english).isEmpty)
  }

  @Test func legLabelGroupsDigitsInTheViewersLocale() {
    #expect(GlobeFormat.legLabel(mode: "fly", distanceKm: 11_140, durationMins: nil, locale: Locale(identifier: "de_DE")) == "fly · 11.140 km")
  }

  @Test func nodeRadiusRunsFrom4To9ByVisits() {
    #expect(GlobeFormat.nodeRadius(visitCount: 0) == 4)
    #expect(GlobeFormat.nodeRadius(visitCount: 1) == 4)
    #expect(GlobeFormat.nodeRadius(visitCount: 10) == 9)
    #expect(GlobeFormat.nodeRadius(visitCount: 40) == 9)
    let five = GlobeFormat.nodeRadius(visitCount: 5)
    #expect(five > 6 && five < 7)
  }
}

struct GlobeMappingTests {
  private func arc(_ trip: String, _ from: String, _ to: String, _ day: Int?) -> Loci_Travelhistory_GlobeArc {
    var arc = Loci_Travelhistory_GlobeArc()
    arc.tripID = trip
    arc.fromName = from
    arc.toName = to
    arc.fromLat = 38.7
    arc.fromLon = -9.1
    arc.toLat = 41.1
    arc.toLon = -8.6
    arc.distanceKm = 274
    arc.mode = "rail"
    if let day { arc.occurredAt = Google_Protobuf_Timestamp(date: Date(timeIntervalSince1970: Double(day) * 86_400)) }
    return arc
  }

  @Test func legKeysDoNotDependOnPosition() {
    let a = arc("t1", "Lisbon", "Porto", 100)
    let b = arc("t1", "Porto", "Madrid", 101)
    let c = arc("t2", "Madrid", "Lisbon", nil)
    let first = Dictionary(uniqueKeysWithValues: GlobeMapping.legs([a, b, c]).map { ("\($0.fromName)>\($0.toName)", $0.id) })
    let reordered = Dictionary(uniqueKeysWithValues: GlobeMapping.legs([c, a, b]).map { ("\($0.fromName)>\($0.toName)", $0.id) })
    #expect(first == reordered)
    // A new leg arriving at the top does not move anyone else's key (web keys by index).
    let withNew = GlobeMapping.legs([arc("t3", "Porto", "Faro", 200), a, b, c]).map(\.id)
    #expect(Set(first.values).isSubset(of: Set(withNew)))
  }

  @Test func legKeyIsTripFromToAndWhen() {
    let keys = GlobeMapping.legs([arc("t1", "Lisbon", "Porto", 1), arc("", "Porto", "Lisbon", nil)]).map(\.id)
    #expect(keys == ["t1|Lisbon|Porto|86400", "-|Porto|Lisbon|-"])
  }

  @Test func theSameLegTwiceGetsDistinctKeys() {
    let legs = GlobeMapping.legs([arc("t1", "Lisbon", "Porto", 5), arc("t1", "Lisbon", "Porto", 5)])
    #expect(legs.map(\.id) == ["t1|Lisbon|Porto|432000", "t1|Lisbon|Porto|432000#2"])
    #expect(Set(legs.map(\.id)).count == 2)
  }

  @Test func missingFieldsReadAsNothing() {
    var response = Loci_Travelhistory_GetGlobeDataResponse()
    var city = Loci_Travelhistory_VisitedCity()
    city.cityName = "Évora"
    response.cities = [city]
    let data = GlobeMapping.data(response)
    #expect(data.summary == TravelSummary())
    #expect(data.summary.periodDays == 365)
    #expect(data.backfilled == false)
    #expect(data.cities[0].visitCount == 0)
    #expect(data.cities[0].country.isEmpty)
    #expect(data.cities[0].lastVisitAt == nil)
    #expect(!data.cities[0].id.isEmpty)
    #expect(!data.isEmpty)
  }

  @Test func summaryCarriesThePreviousPeriod() {
    var summary = Loci_Travelhistory_TravelSummary()
    summary.citiesVisited = 7
    summary.citiesVisitedPrevPeriod = 5
    summary.countriesVisitedPrevPeriod = 4
    summary.poisVisitedPrevPeriod = 40
    summary.distanceKm = 1234.5
    let mapped = GlobeMapping.summary(summary)
    #expect(mapped.citiesVisitedPrev == 5)
    #expect(mapped.countriesVisitedPrev == 4)
    #expect(mapped.poisVisitedPrev == 40)
    #expect(mapped.distanceKm == 1234.5)
    #expect(mapped.periodDays == 365)
  }

  @Test func windowCountsDriveTheTrendOnceTheServerSendsThem() {
    // v5.29.0: *_prev_period is the previous window's count; compare it with *_this_period.
    var summary = Loci_Travelhistory_TravelSummary()
    summary.citiesVisited = 7
    summary.countriesVisited = 5
    summary.poisVisited = 48
    summary.citiesVisitedThisPeriod = 3
    summary.citiesVisitedPrevPeriod = 2
    summary.countriesVisitedThisPeriod = 1
    summary.countriesVisitedPrevPeriod = 2
    summary.poisVisitedThisPeriod = 12
    summary.poisVisitedPrevPeriod = 0
    let mapped = GlobeMapping.summary(summary)
    #expect(mapped.hasWindowCounts)
    #expect(mapped.citiesVisitedThis == 3)
    #expect(mapped.citiesTrend == 50)
    #expect(mapped.countriesTrend == -50)
    #expect(mapped.poisTrend == nil)  // nothing in the previous window: no baseline, no arrow
  }

  @Test func olderServersKeepTheTotalAgainstPreviousTotalTrend() {
    // Before v5.29.0 there are no window counts; *_prev_period was the total when the window opened.
    var summary = Loci_Travelhistory_TravelSummary()
    summary.citiesVisited = 7
    summary.countriesVisited = 5
    summary.poisVisited = 48
    summary.citiesVisitedPrevPeriod = 5
    summary.countriesVisitedPrevPeriod = 4
    summary.poisVisitedPrevPeriod = 40
    let mapped = GlobeMapping.summary(summary)
    #expect(!mapped.hasWindowCounts)
    #expect(mapped.citiesTrend == 40)
    #expect(mapped.countriesTrend == 25)
    #expect(mapped.poisTrend == 20)
  }

  @Test func oneNonZeroWindowCountSwitchesEveryStat() {
    var summary = TravelSummary()
    summary.citiesVisited = 7
    summary.countriesVisited = 5
    summary.poisVisited = 48
    summary.citiesVisitedPrev = 4
    summary.countriesVisitedPrev = 1
    summary.poisVisitedPrev = 10
    summary.poisVisitedThis = 5
    #expect(summary.hasWindowCounts)
    #expect(summary.citiesTrend == -100)  // 0 this window against 4 last window
    #expect(summary.countriesTrend == -100)
    #expect(summary.poisTrend == -50)
  }

  @Test func recentsCityMatchIgnoresCaseAndAccents() {
    let cities = [
      RecentCity(name: "Évora", country: "", interactionCount: 1, lastActivity: nil, interactions: []),
      RecentCity(name: "Lisbon", country: "", interactionCount: 1, lastActivity: nil, interactions: []),
    ]
    #expect(RecentCityMatch.find("evora", in: cities)?.name == "Évora")
    #expect(RecentCityMatch.find(" LISBON ", in: cities)?.name == "Lisbon")
    #expect(RecentCityMatch.find("Porto", in: cities) == nil)
    #expect(RecentCityMatch.find("", in: cities) == nil)
  }
}

@MainActor struct GlobeStoreTests {
  private struct Failing: TravelHistoryService {
    func globeData() async throws -> GlobeData { throw APIError.custom("Could not load your travels.") }
  }

  @Test func loadsAndSplitsArcsOverTheAntimeridian() async {
    let store = GlobeStore(service: PreviewTravelHistoryService())
    await store.load()
    #expect(store.phase == .loaded)
    // Five legs, one of them (Auckland → Santiago) drawn as two pieces.
    #expect(store.data.legs.count == 5)
    #expect(store.arcs.count == 6)
  }

  @Test func aFailureWithNothingLoadedIsAnErrorNotAnEmptyGlobe() async {
    let store = GlobeStore(service: Failing())
    await store.load()
    #expect(store.phase == .failed("Could not load your travels."))
    #expect(store.error == nil)
  }

  @Test func anEmptyBackfilledHistoryLoads() async {
    let store = GlobeStore(service: PreviewTravelHistoryService(data: .previewEmpty))
    await store.load()
    #expect(store.phase == .loaded)
    #expect(store.data.isEmpty && store.data.backfilled)
  }
}
