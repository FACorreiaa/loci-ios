import Foundation
import LociConnectProto
import MapKit
import SwiftUI
import Testing

@testable import loci

/// The result page's model: day grouping, share text, the calendar schedule,
/// the Pro gate and the reducer's partial-failure path. Web's rules, checked.
struct ResultsParityTests {
  private func stop(
    _ name: String, day: Int? = nil, priority: Int? = nil, lat: Double = 0, lon: Double = 0, address: String = ""
  ) -> Loci_Poi_POIDetailedInfo {
    var poi = Loci_Poi_POIDetailedInfo()
    poi.id = name.lowercased().replacingOccurrences(of: " ", with: "-")
    poi.name = name
    if let day { poi.day = Int32(day) }
    if let priority { poi.priority = Int32(priority) }
    if lat != 0 || lon != 0 {
      poi.latitude = lat
      poi.longitude = lon
    }
    poi.address = address
    return poi
  }

  // MARK: - Day grouping

  @Test func groupsByServerDayAndLabelsByPosition() {
    let groups = DayGrouping.groups([stop("C", day: 3), stop("A", day: 1, priority: 2), stop("B", day: 1, priority: 1), stop("D", day: 3)])
    #expect(groups.map(\.number) == [1, 2])
    #expect(groups[0].stops.map(\.name) == ["B", "A"])
    #expect(groups[1].stops.map(\.name) == ["C", "D"])
  }

  @Test func chunksOfFourWhenNoStopHasADay() {
    let groups = DayGrouping.groups((1...9).map { stop("S\($0)") })
    #expect(groups.map(\.stops.count) == [4, 4, 1])
    #expect(groups.map(\.number) == [1, 2, 3])
  }

  @Test func extrasExcludeItineraryStopsAndDuplicates() {
    let planned = [stop("A"), stop("B")]
    let extras = DayGrouping.extras(all: [stop("A"), stop("C"), stop("C"), stop("D")], itinerary: planned)
    #expect(extras.map(\.name) == ["C", "D"])
  }

  @Test func sequenceCountsAcrossDays() {
    let groups = DayGrouping.groups([stop("A", day: 1), stop("B", day: 1), stop("C", day: 2)])
    let sequence = DayGrouping.sequence(groups)
    #expect(sequence["a"] == 1)
    #expect(sequence["b"] == 2)
    #expect(sequence["c"] == 3)
  }

  @Test func listsAreOneGroupAndItinerariesUseDays() {
    var state = SearchState()
    state.destination = .hotels
    state.hotels = [stop("H1"), stop("H2"), stop("H3"), stop("H4"), stop("H5")]
    #expect(state.dayGroups.count == 1)
    #expect(state.dayGroups[0].stops.count == 5)
    var itinerary = SearchState()
    var response = Loci_Chat_AiCityResponse()
    response.itineraryResponse.pointsOfInterest = [stop("A", day: 1), stop("B", day: 2)]
    response.pointsOfInterest = [stop("A", day: 1), stop("Z")]
    itinerary.adopt(response)
    #expect(itinerary.dayGroups.count == 2)
    #expect(itinerary.extras.map(\.name) == ["Z"])
  }

  // MARK: - Full map flyover

  @MainActor private func mapData(_ stops: [Loci_Poi_POIDetailedInfo], showsDays: Bool = true) -> ResultsMapData {
    let groups = DayGrouping.groups(stops)
    return ResultsMapData(groups: groups, extras: [], sequence: DayGrouping.sequence(groups), showsDays: showsDays, alerts: [])
  }

  @MainActor @Test func flyoverStartsAtDayOnesFirstPin() {
    let data = mapData([
      stop("B", day: 2, lat: 41.9, lon: 12.47), stop("A", day: 1, lat: 41.89, lon: 12.49), stop("C", day: 1, lat: 41.88, lon: 12.48),
    ])
    #expect(data.flyoverStart?.name == "A")
  }

  @MainActor @Test func flyoverSkipsStopsWithoutCoordinates() {
    let data = mapData([stop("A", day: 1), stop("B", day: 1, lat: 41.89, lon: 12.49)])
    #expect(data.flyoverStart?.name == "B")
  }

  @MainActor @Test func flyoverFallsBackToTheFirstPinWithoutDays() {
    let data = mapData([stop("H1", lat: 38.7, lon: -9.1), stop("H2", lat: 38.71, lon: -9.14)], showsDays: false)
    #expect(data.pins.allSatisfy { $0.day == 0 })
    #expect(data.flyoverStart?.name == "H1")
  }

  @MainActor @Test func flyoverIsNilWhenNothingHasCoordinates() {
    #expect(mapData([stop("A", day: 1), stop("B", day: 2)]).flyoverStart == nil)
  }

  @MainActor @Test func flyoverCameraIsPitchedAndClose() {
    let camera = ResultsMapData.flyoverCamera(at: .init(latitude: 41.8902, longitude: 12.4922))
    #expect(camera.pitch == 60)
    #expect(camera.distance == 900)
    #expect(camera.heading == 30)
    #expect(camera.centerCoordinate.latitude == 41.8902)
    #expect(camera.centerCoordinate.longitude == 12.4922)
  }

  // MARK: - Share text

  @Test func shareTextMatchesWebShape() {
    let groups = DayGrouping.groups([
      stop("A", day: 1), stop("B", day: 1), stop("C", day: 1), stop("D", day: 1), stop("E", day: 1), stop("F", day: 2),
      stop("G", day: 3), stop("H", day: 4), stop("I", day: 5),
    ])
    let text = ShareText.build(title: "Rome on foot", groups: groups)
    let lines = text.components(separatedBy: "\n")
    #expect(lines[0] == "Rome on foot")
    #expect(lines[1] == "Day 1 · A, B, C, D +1 more")
    #expect(lines[4] == "Day 4 · H")
    #expect(lines[5] == "+1 more day")
    #expect(lines.suffix(2) == ["Generated from Loci", "https://lociai.fyi"])
  }

  // MARK: - Google Maps

  @Test func googleMapsRouteUsesCoordinatesAndCapsWaypoints() throws {
    let stops = (1...12).map { stop("S\($0)", lat: 41.0 + Double($0) / 100, lon: 12.0) }
    let url = try #require(GoogleMapsRoute.url(for: stops, cityName: "Rome"))
    let query = try #require(url.query)
    #expect(query.contains("origin=41.01,12.0"))
    #expect(query.contains("destination=41.12,12.0"))
    #expect(query.contains("travelmode=walking"))
    let waypoints = try #require(query.components(separatedBy: "waypoints=").last?.components(separatedBy: "&").first)
    #expect(waypoints.components(separatedBy: "%7C").count == GoogleMapsRoute.maxWaypoints)
  }

  @Test func googleMapsFallsBackToNamesWithoutCoordinates() throws {
    let url = try #require(GoogleMapsRoute.url(for: [stop("Pantheon", address: "Piazza della Rotonda")], cityName: "Rome"))
    #expect(url.absoluteString.contains("destination=Pantheon%2C%20Piazza%20della%20Rotonda%2C%20Rome"))
  }

  // MARK: - Calendar schedule

  @Test func calendarEventsStartAtNineWithBuffers() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8)))
    let groups = DayGrouping.groups([stop("A", day: 1), stop("B", day: 1), stop("C", day: 2, address: "Via Roma 1")])
    let events = CalendarSchedule.events(groups: groups, startDate: start, cityName: "Rome", summary: "Trip", calendar: calendar)
    #expect(events.count == 3)
    #expect(calendar.component(.hour, from: events[0].start) == 9)
    #expect(events[0].end.timeIntervalSince(events[0].start) == 90 * 60)
    #expect(events[1].start.timeIntervalSince(events[0].end) == 15 * 60)
    #expect(calendar.component(.day, from: events[2].start) == 9)
    #expect(calendar.component(.hour, from: events[2].start) == 9)
    #expect(events[2].location == "Via Roma 1")
    #expect(events[0].location == "A, Rome")
  }

  // MARK: - Pro gate

  @Test func proGateMatchesWebPlans() {
    for plan in ["premium_monthly", "premium_annual", "premium", "pro", "paid", "explorer", "PRO"] {
      #expect(ProGate.isPro(plan: plan), "\(plan) should be pro")
    }
    #expect(!ProGate.isPro(plan: "free"))
    #expect(!ProGate.isPro(plan: nil))
    let groups = DayGrouping.groups([stop("A", day: 1), stop("B", day: 2)])
    #expect(ProGate.unlocked(groups, isPro: false, gating: true).count == 1)
    #expect(ProGate.unlocked(groups, isPro: true, gating: true).count == 2)
  }

  /// Plan gating is off until there are users to gate: a free plan gets every
  /// day, and the gate reports itself off so the views skip the plan copy.
  @Test func proGateIsOffByDefault() {
    #expect(!PlanGating.enabled)
    let groups = DayGrouping.groups([stop("A", day: 1), stop("B", day: 2)])
    #expect(ProGate.unlocked(groups, isPro: false).count == 2)
    #expect(ProGate.entitled(isPro: false))
    #expect(!ProGate.entitled(isPro: false, gating: true))
  }

  // MARK: - Reducer

  @Test func errorAfterPlacesKeepsThemAndFlagsThePartial() {
    var state = SearchState()
    _ = state.apply(Events.start("s1", domain: .accommodation, city: "Porto"))
    _ = state.apply(Events.hotels(["Hotel A", "Hotel B"], id: "e1"))
    _ = state.apply(Events.error("Model timed out", id: "e2"))
    #expect(state.status == .completedWithError("Model timed out"))
    #expect(state.places.count == 2)
    #expect(state.phase == .done)
    #expect(state.failureMessage == "Model timed out")
  }

  @Test func errorWithNothingIsAPlainFailure() {
    var state = SearchState()
    _ = state.apply(Events.start("s1", domain: .accommodation))
    _ = state.apply(Events.error("Nope", id: "e1"))
    #expect(state.status == .failed("Nope"))
    #expect(state.phase == .skeleton)
  }

  @Test func completeWithLoadFromSessionAsksForAFetch() {
    var state = SearchState()
    _ = state.apply(Events.start("s1", domain: .itinerary))
    var complete = Loci_Chat_StreamEvent()
    complete.eventID = "e9"
    complete.complete.sessionID = "s1"
    complete.complete.loadFromSession = true
    _ = state.apply(complete)
    #expect(state.needsSessionFetch)
    #expect(state.status == .completed)
  }

  @Test func emptyCompleteResultDoesNotWipeTheItinerary() {
    var state = SearchState()
    _ = state.apply(Events.start("s1", domain: .itinerary))
    var itinerary = Loci_Chat_StreamEvent()
    itinerary.eventID = "e1"
    itinerary.itinerary.cityResponse.itineraryResponse.pointsOfInterest = [stop("A", day: 1)]
    _ = state.apply(itinerary)
    var complete = Loci_Chat_StreamEvent()
    complete.eventID = "e2"
    complete.complete.sessionID = "s1"
    complete.complete.result = Loci_Chat_AiCityResponse()
    _ = state.apply(complete)
    #expect(state.places.count == 1)
    #expect(!state.needsSessionFetch)
  }

  @Test func restoredListsReadTheTypedFieldsAndTheOldFallback() {
    var response = Loci_Chat_AiCityResponse()
    response.hotels = [stop("H1")]
    let link = SessionLink(destination: .hotels, sessionId: "s1", cityName: "Porto", domain: "accommodation")
    #expect(SearchState.restored(link: link, result: response).hotels.map(\.name) == ["H1"])
    var old = Loci_Chat_AiCityResponse()
    old.pointsOfInterest = [stop("R1")]
    let dining = SessionLink(destination: .restaurants, sessionId: "s2", cityName: "Porto", domain: "dining")
    #expect(SearchState.restored(link: dining, result: old).restaurants.map(\.name) == ["R1"])
  }

  // MARK: - Cards

  @Test func imageURLPrefersCredits() throws {
    var poi = stop("A")
    poi.images = ["https://example.com/bare.jpg"]
    #expect(poi.imageURL?.absoluteString == "https://example.com/bare.jpg")
    var credit = Loci_Poi_POIImage()
    credit.url = "https://example.com/credited.jpg"
    poi.imageCredits = [credit]
    #expect(poi.imageURL?.absoluteString == "https://example.com/credited.jpg")
    #expect(stop("B").imageURL == nil)
  }

  @Test func metaLineFollowsTheDomain() throws {
    var hotel = stop("H")
    hotel.starRating = "4"
    hotel.amenities = "Pool, Spa, Gym, Bar, Parking"
    #expect(StopMeta.line(for: hotel, destination: .hotels) == "4★ · Pool · Spa · Gym · Bar")
    var restaurant = stop("R")
    restaurant.cuisineType = "Roman"
    restaurant.priceLevel = "€€"
    let weekday = Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: Date()) - 1]
    restaurant.openingHours = [weekday: "12:00–23:00"]
    #expect(StopMeta.line(for: restaurant, destination: .restaurants) == "Roman · Today 12:00–23:00 · €€")
    #expect(StopMeta.line(for: stop("P"), destination: .itinerary) == nil)
  }
}
