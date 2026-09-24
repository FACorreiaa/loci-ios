import Foundation
import LociConnectProto

/// Everything one search has produced so far, built up event by event from
/// ChatService.StreamChat. Mirrors what web keeps in its live-stream store
/// (loci-client/src/lib/streaming/live-stream-store.ts).
nonisolated struct SearchState: Equatable, Sendable {
  enum Status: Equatable, Sendable {
    case idle
    case streaming
    /// The client lost the stream; the server may still be generating.
    case detached
    case completed
    case failed(String)
    /// ERROR arrived after places had already streamed: web keeps the results
    /// and shows the error on the status rail. Not a dead end.
    case completedWithError(String)
  }

  /// What the page shows, in web's `ItineraryStreamView` terms.
  enum Phase: Equatable, Sendable {
    /// Nothing to show yet: skeleton cards.
    case skeleton
    /// Places are in, more may come (photos, days).
    case enriching
    case done
  }

  var sessionId: String?
  var destination: SearchDestination = .itinerary
  /// The server's domain name for the route's `domain` query item (web sends the same).
  var domain: String?
  var cityName: String?
  var query = ""
  var status: Status = .idle

  /// Tokens, appended as they arrive, before any structured result.
  var text = ""
  var progressStage: String?
  var progressPercent: Int?

  var cityData: Loci_City_GeneralCityData?
  var itinerary: Loci_Chat_AiCityResponse?
  var generalPOIs: [Loci_Poi_POIDetailedInfo] = []
  var hotels: [Loci_Poi_POIDetailedInfo] = []
  var restaurants: [Loci_Poi_POIDetailedInfo] = []
  var activities: [Loci_Poi_POIDetailedInfo] = []

  /// The newest event id: the `resume_token` for a reattach.
  var lastEventId: String?
  /// `(event_id, payload case)` pairs already applied. The server reuses one
  /// event id for several events (chat_process_stream.go, recommendationRunID),
  /// so the id alone would drop real events.
  var seen: Set<String> = []

  /// The server's `planned_days`; 0 when unknown.
  var plannedDays = 0

  /// A multi-city search's route (chat.proto RoutePayload); nil for one city.
  var route: Loci_Chat_RoutePayload?
  /// Each city's own results, in route order. Empty for one city.
  var stops: [StopResult] = []
  var isMultiCity: Bool { stops.count >= 2 }
  /// COMPLETE said the result is not on the stream: fetch it with GetChatSession.
  var needsSessionFetch = false

  var isActive: Bool { status == .streaming || status == .detached }

  /// The failure a user's Stop leaves behind. Not a snag, so the header stays quiet.
  static let stoppedMessage = "Stopped."

  var phase: Phase {
    if !hasResult { return .skeleton }
    return isActive ? .enriching : .done
  }

  /// The text of a failure, whether it ended the search or came after results.
  var failureMessage: String? {
    switch status {
    case .failed(let message), .completedWithError(let message): message
    default: nil
    }
  }

  /// Itinerary stops grouped by day (web `groupStopsByDay`); lists are one group.
  var dayGroups: [DayGroup] {
    switch destination {
    case .itinerary: DayGrouping.groups(places)
    default: places.isEmpty ? [] : [DayGroup(number: 1, stops: places)]
    }
  }

  /// Top-level places outside the itinerary: "More to explore".
  var extras: [Loci_Poi_POIDetailedInfo] {
    guard destination == .itinerary, let itinerary else { return [] }
    let planned = itinerary.itineraryResponse.pointsOfInterest
    guard !planned.isEmpty else { return [] }
    return DayGrouping.extras(all: itinerary.pointsOfInterest + generalPOIs, itinerary: planned)
  }

  var link: SessionLink? {
    sessionId.map { SessionLink(destination: destination, sessionId: $0, cityName: cityName, domain: domain) }
  }

  /// The places for this search's result page.
  var places: [Loci_Poi_POIDetailedInfo] {
    switch destination {
    case .hotels: hotels
    case .restaurants: restaurants
    case .activities: activities
    case .itinerary: itineraryPlaces
    }
  }

  private var itineraryPlaces: [Loci_Poi_POIDetailedInfo] {
    guard let itinerary else { return generalPOIs }
    if !itinerary.itineraryResponse.pointsOfInterest.isEmpty { return itinerary.itineraryResponse.pointsOfInterest }
    if !itinerary.pointsOfInterest.isEmpty { return itinerary.pointsOfInterest }
    return generalPOIs
  }

  var hasResult: Bool { !places.isEmpty || itinerary != nil }

  /// Every place from every event, without repeats: what web's /nearme shows
  /// (general POIs, restaurants, hotels and activities together).
  var allPlaces: [Loci_Poi_POIDetailedInfo] {
    var seenKeys = Set<String>()
    return (itineraryPlaces + hotels + restaurants + activities).filter { poi in
      seenKeys.insert(poi.stableID).inserted
    }
  }
}

/// One city of a multi-city search: the same state a single-city search
/// builds, per city.
nonisolated struct StopResult: Equatable, Sendable {
  var index: Int
  var cityName: String
  var sessionId: String
  /// Trip-wide day numbers spent here.
  var dayNumbers: [Int]
  var state = SearchState()
  /// Set when this city failed; the others go on.
  var error: String?
}

/// What applying an event asks the controller to do.
nonisolated enum SearchEffect: Equatable, Sendable {
  /// The server named the session: navigate to its result page (web: onStart → getDomainRoute).
  case started(SessionLink)
  case completed
  case failed(message: String, retryable: Bool)
}

nonisolated extension SearchState {
  /// Apply one stream event. Returns an effect for the start, the end and errors.
  @discardableResult mutating func apply(_ event: Loci_Chat_StreamEvent) -> SearchEffect? {
    guard let payload = event.payload else { return nil }
    if !event.eventID.isEmpty {
      let stop = event.hasStopIndex ? String(event.stopIndex) : "-"
      let key = "\(event.eventID)|\(payload.caseName)|\(stop)"
      guard seen.insert(key).inserted else { return nil }
      lastEventId = event.eventID
    }

    if case .route(let route) = payload {
      absorb(route: route)
      return nil
    }
    // One city of a multi-city search: its events build that city's state.
    // A city's error is that city's; the search goes on.
    if event.hasStopIndex, let i = stops.firstIndex(where: { $0.index == Int(event.stopIndex) }) {
      if case .error(let error) = payload {
        stops[i].error = error.userMessage.isEmpty ? "This city could not be planned." : error.userMessage
        return nil
      }
      var inner = event
      inner.clearStopIndex()
      inner.eventID = ""  // already de-duplicated above
      stops[i].state.apply(inner)
      // The first city stands in for the flat fields, so every existing view has something.
      if i == 0 { adoptFirstStop(stops[0].state) }
      return nil
    }

    switch payload {
    case .start(let start):
      sessionId = start.sessionID
      domain = start.domain.routeName
      destination = SearchDestination(domain: start.domain.routeName)
      if start.hasCityName, !start.cityName.isEmpty { cityName = start.cityName }
      status = .streaming
      return link.map(SearchEffect.started)
    case .token(let token), .partial(let token):
      text += token.text
      // The newest signal wins: once words arrive the header says "is writing"
      // until the server names another stage.
      progressStage = nil
      progressPercent = nil
    case .progress(let progress):
      progressStage = progress.stage
      progressPercent = progress.hasPercent ? Int(progress.percent) : nil
    case .cityData(let data):
      absorb(city: data.hasGeneralCityData ? data.generalCityData : nil)
    case .itinerary(let payload):
      if payload.hasCityResponse {
        itinerary = payload.cityResponse
        absorb(city: payload.cityResponse.hasGeneralCityData ? payload.cityResponse.generalCityData : nil)
      }
    case .generalPois(let payload):
      generalPOIs = payload.pois
      absorb(city: payload.hasGeneralCityData ? payload.generalCityData : nil)
    case .hotels(let payload):
      hotels = payload.pois
      absorb(city: payload.hasGeneralCityData ? payload.generalCityData : nil)
    case .restaurants(let payload):
      restaurants = payload.pois
      absorb(city: payload.hasGeneralCityData ? payload.generalCityData : nil)
    case .activities(let payload):
      activities = payload.activities
      absorb(city: payload.hasGeneralCityData ? payload.generalCityData : nil)
    case .error(let error):
      let message = error.userMessage.isEmpty ? "The search failed." : error.userMessage
      status = hasResult ? .completedWithError(message) : .failed(message)
      return .failed(message: error.userMessage, retryable: error.retryable)
    case .complete(let complete):
      if !complete.sessionID.isEmpty { sessionId = complete.sessionID }
      if complete.hasResult, complete.result.hasContent, destination == .itinerary || itinerary == nil {
        adopt(complete.result)
      }
      needsSessionFetch = complete.loadFromSession && !hasResult
      status = .completed
      return .completed
    case .route:
      break  // handled above
    }
    return nil
  }

  /// Take a full AiCityResponse, from the stream, the phone's copy or GetChatSession.
  mutating func adopt(_ result: Loci_Chat_AiCityResponse) {
    itinerary = result
    if result.hasItineraryResponse { plannedDays = Int(result.itineraryResponse.plannedDays) }
    if !result.hotels.isEmpty { hotels = result.hotels }
    if !result.restaurants.isEmpty { restaurants = result.restaurants }
    if !result.activities.isEmpty { activities = result.activities }
    absorb(city: result.hasGeneralCityData ? result.generalCityData : nil)
  }

  /// A ROUTE builds the cities; the one carrying the trip id keeps what each already has.
  private mutating func absorb(route: Loci_Chat_RoutePayload) {
    self.route = route
    stops = route.stops.map { ref in
      var stop = stops.first { $0.index == Int(ref.index) }
        ?? StopResult(index: Int(ref.index), cityName: ref.cityName, sessionId: ref.sessionID, dayNumbers: ref.dayNumbers.map(Int.init))
      stop.cityName = ref.cityName
      stop.sessionId = ref.sessionID
      stop.dayNumbers = ref.dayNumbers.map(Int.init)
      stop.state.cityName = ref.cityName
      stop.state.sessionId = ref.sessionID
      return stop
    }
  }

  private mutating func adoptFirstStop(_ first: SearchState) {
    if let itinerary = first.itinerary { self.itinerary = itinerary }
    if !first.generalPOIs.isEmpty { generalPOIs = first.generalPOIs }
    if !first.hotels.isEmpty { hotels = first.hotels }
    if !first.restaurants.isEmpty { restaurants = first.restaurants }
    if !first.activities.isEmpty { activities = first.activities }
    if let city = first.cityData { cityData = city }
    if first.plannedDays > 0 { plannedDays = first.plannedDays }
  }

  private mutating func absorb(city: Loci_City_GeneralCityData?) {
    guard let city else { return }
    cityData = city
    if cityName == nil, !city.city.isEmpty { cityName = city.city }
  }
}

nonisolated extension Loci_Chat_StreamEvent.OneOf_Payload {
  var caseName: String {
    switch self {
    case .start: "start"
    case .token: "token"
    case .partial: "partial"
    case .cityData: "city_data"
    case .itinerary: "itinerary"
    case .generalPois: "general_pois"
    case .hotels: "hotels"
    case .restaurants: "restaurants"
    case .activities: "activities"
    case .progress: "progress"
    case .error: "error"
    case .complete: "complete"
    case .route: "route"
    }
  }
}

nonisolated extension Loci_Chat_DomainType {
  /// The lowercase names web puts in the `domain` query item.
  var routeName: String {
    switch self {
    case .accommodation: "accommodation"
    case .dining: "dining"
    case .activities: "activities"
    case .itinerary: "itinerary"
    case .transport: "transport"
    default: "general"
    }
  }
}

nonisolated extension Loci_Poi_POIDetailedInfo {
  /// A key for ForEach and map selection. The server sometimes sends places
  /// with no id, so those fall back to name plus coordinates.
  var stableID: String { id.isEmpty ? "\(name)|\(latitude)|\(longitude)" : id }
}

nonisolated extension Loci_Chat_AiCityResponse {
  /// Web's `responseHasContent`: a COMPLETE with an empty result must not wipe
  /// what the itinerary event already delivered.
  var hasContent: Bool {
    !pointsOfInterest.isEmpty || !hotels.isEmpty || !restaurants.isEmpty || !activities.isEmpty
      || (hasItineraryResponse && !itineraryResponse.pointsOfInterest.isEmpty)
  }
}
