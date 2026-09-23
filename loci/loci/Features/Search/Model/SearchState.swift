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

  var isActive: Bool { status == .streaming || status == .detached }

  /// The failure a user's Stop leaves behind. Not a snag, so the header stays quiet.
  static let stoppedMessage = "Stopped."

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
      let key = "\(event.eventID)|\(payload.caseName)"
      guard seen.insert(key).inserted else { return nil }
      lastEventId = event.eventID
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
      status = .failed(error.userMessage.isEmpty ? "The search failed." : error.userMessage)
      return .failed(message: error.userMessage, retryable: error.retryable)
    case .complete(let complete):
      if !complete.sessionID.isEmpty { sessionId = complete.sessionID }
      if complete.hasResult, destination == .itinerary || itinerary == nil { itinerary = complete.result }
      status = .completed
      return .completed
    }
    return nil
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
