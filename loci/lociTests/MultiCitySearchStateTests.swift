import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Multi-city stream events: a ROUTE, then each city's events tagged with its index.
/// One city of a test route.
struct RouteCity {
  let name: String
  let session: String
  let days: [Int32]
}

enum MultiEvents {
  static func route(_ cities: [RouteCity], tripID: String? = nil, id: String = "r0") -> Loci_Chat_StreamEvent {
    var event = Loci_Chat_StreamEvent()
    event.eventID = id
    event.route.stops = cities.enumerated().map { i, c in
      var ref = Loci_Chat_StopRef()
      ref.index = Int32(i)
      ref.cityName = c.name
      ref.sessionID = c.session
      ref.dayNumbers = c.days
      return ref
    }
    event.route.outline = cities.map(\.name).joined(separator: " → ")
    if let tripID { event.route.tripID = tripID }
    return event
  }

  static func pois(stop: Int32, _ names: [String], id: String) -> Loci_Chat_StreamEvent {
    var event = Loci_Chat_StreamEvent()
    event.eventID = id
    event.stopIndex = stop
    event.generalPois.pois = names.map { name in
      var poi = Loci_Poi_POIDetailedInfo()
      poi.name = name
      return poi
    }
    return event
  }

  static func error(stop: Int32, _ message: String, id: String) -> Loci_Chat_StreamEvent {
    var event = Loci_Chat_StreamEvent()
    event.eventID = id
    event.stopIndex = stop
    event.error.userMessage = message
    return event
  }
}

@Suite("Multi-city search")
struct MultiCitySearchStateTests {
  let lisbonPorto = [RouteCity(name: "Lisbon", session: "s0", days: [1, 2]), RouteCity(name: "Porto", session: "s1", days: [3])]

  @Test func routeBuildsStopsAndTaggedEventsGoToTheirCity() {
    var state = SearchState()
    state.apply(Events.start("s0", domain: .itinerary))
    state.apply(MultiEvents.route(lisbonPorto))
    #expect(state.isMultiCity)
    #expect(state.stops.map(\.cityName) == ["Lisbon", "Porto"])

    state.apply(MultiEvents.pois(stop: 1, ["Ribeira"], id: "p1"))
    #expect(state.stops[0].state.generalPOIs.isEmpty)
    #expect(state.stops[1].state.generalPOIs.first?.name == "Ribeira")
  }

  @Test func aCitysErrorDoesNotFailTheSearch() {
    var state = SearchState()
    state.apply(Events.start("s0", domain: .itinerary))
    state.apply(MultiEvents.route(lisbonPorto))
    let effect = state.apply(MultiEvents.error(stop: 1, "Porto failed", id: "x1"))
    #expect(effect == nil)
    #expect(state.status == .streaming)
    #expect(state.stops[1].error == "Porto failed")
    #expect(state.stops[0].error == nil)
  }

  @Test func theSecondRouteKeepsEachCitysResults() {
    var state = SearchState()
    state.apply(MultiEvents.route(lisbonPorto))
    state.apply(MultiEvents.pois(stop: 0, ["Belém"], id: "p0"))
    state.apply(MultiEvents.route(lisbonPorto, tripID: "t1", id: "r1"))
    #expect(state.stops[0].state.generalPOIs.first?.name == "Belém")
    #expect(state.route?.tripID == "t1")
  }

  @Test func theFirstCityStandsInForTheFlatFields() {
    var state = SearchState()
    state.apply(MultiEvents.route(lisbonPorto))
    state.apply(MultiEvents.pois(stop: 0, ["Belém"], id: "p0"))
    #expect(state.generalPOIs.first?.name == "Belém")
  }

  @Test func aSingleCityStreamIsUnchanged() {
    var state = SearchState()
    state.apply(Events.hotels(["Inn"], id: "h1"))
    #expect(!state.isMultiCity)
    #expect(state.hotels.first?.name == "Inn")
  }
}

@Suite("Multi-city request")
struct MultiCityRequestTests {
  func envelope() -> SearchEnvelope {
    SearchEnvelope(
      sessionId: nil,
      requestId: "r",
      profileId: nil,
      lastEventId: nil,
      query: "trip",
      cityName: nil,
      domain: nil,
      latitude: nil,
      longitude: nil,
      startedAt: .now,
      finished: false,
      notified: false
    )
  }

  @MainActor @Test func stopsGoIntoTheRequest() {
    var env = envelope()
    env.stops = [StopInput(cityName: "Lisbon", nights: 3), StopInput(cityName: "Porto", nights: nil)]
    env.suggestOrder = true
    let request = SearchSessionController.request(from: env, resuming: false)
    #expect(request.stops.map(\.cityName) == ["Lisbon", "Porto"])
    #expect(request.stops[0].nights == 3)
    #expect(!request.stops[1].hasNights)
    #expect(request.suggestOrder)
  }

  @Test func oldEnvelopesStillDecode() throws {
    let json = #"{"requestId":"r","query":"q","startedAt":0,"finished":false,"notified":false}"#
    let env = try JSONDecoder().decode(SearchEnvelope.self, from: Data(json.utf8))
    #expect(env.stops == nil)
  }
}

@Suite("Multi-city format")
struct MultiCityFormatTests {
  /// The same strings web renders (multi-city-view.ts), so both apps read alike.
  @Test func matchesWeb() {
    var leg = Loci_Trip_TripLeg()
    leg.mode = "train"
    leg.durationMins = 194
    leg.distanceKm = 274.4
    #expect(MultiCityFormat.leg(leg) == "Train · ≈3h14 · 274 km")
    leg.mode = "drive"
    leg.durationMins = 30
    leg.distanceKm = 40
    #expect(MultiCityFormat.leg(leg) == "Drive · ≈30 min · 40 km")
    let stop = StopResult(index: 0, cityName: "Lisbon", sessionId: "s", dayNumbers: [1, 2])
    #expect(MultiCityFormat.chip(stop) == "Lisbon · 2n")
  }
}
