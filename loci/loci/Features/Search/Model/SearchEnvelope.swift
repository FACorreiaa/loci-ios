import Foundation
import LociConnectProto
import SwiftProtobuf

/// What survives the app being suspended or killed mid-search: enough to
/// reattach (session id + resume token) and to rebuild the request. Mirrors
/// web's `sessionStorage["active_streaming_session"]` envelope.
nonisolated struct SearchEnvelope: Codable, Equatable, Sendable {
  var sessionId: String?
  var requestId: String
  var profileId: String?
  var lastEventId: String?
  var query: String
  var cityName: String?
  var domain: String?
  var latitude: Double?
  var longitude: Double?
  var startedAt: Date
  var finished: Bool
  var notified: Bool
}

/// Files in Application Support: the active search's envelope, and the last
/// finished search's result, because GetChatSession cannot return hotel,
/// restaurant or activity lists (the proto AiCityResponse has no fields for them).
nonisolated struct SearchStore: Sendable {
  let directory: URL

  init(directory: URL? = nil) {
    self.directory =
      directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "search")
  }

  private var envelopeURL: URL { directory.appending(path: "active-search.json") }

  private func resultURL(_ sessionId: String) -> URL { directory.appending(path: "result-\(sessionId).bin") }

  func loadEnvelope() -> SearchEnvelope? {
    guard let data = try? Data(contentsOf: envelopeURL) else { return nil }
    return try? JSONDecoder().decode(SearchEnvelope.self, from: data)
  }

  func save(_ envelope: SearchEnvelope) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    guard let data = try? JSONEncoder().encode(envelope) else { return }
    try? data.write(to: envelopeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  func clearEnvelope() { try? FileManager.default.removeItem(at: envelopeURL) }

  /// Keep one finished result per session, as the pieces the page needs.
  func saveResult(_ state: SearchState) {
    guard let sessionId = state.sessionId else { return }
    var snapshot = Loci_Chat_StreamEvent()
    var payload = Loci_Chat_AiCityResponse()
    if let itinerary = state.itinerary { payload = itinerary }
    if let city = state.cityData, !payload.hasGeneralCityData { payload.generalCityData = city }
    payload.hotels = state.hotels
    payload.restaurants = state.restaurants
    payload.activities = state.activities
    if payload.pointsOfInterest.isEmpty { payload.pointsOfInterest = state.generalPOIs }
    payload.sessionID = sessionId
    snapshot.complete.result = payload
    snapshot.complete.sessionID = sessionId
    snapshot.message = state.text
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? snapshot.serializedData().write(to: resultURL(sessionId), options: .atomic)
  }

  /// Rebuild a finished search from disk, if this device ran it.
  func loadResult(for link: SessionLink) -> SearchState? {
    guard let data = try? Data(contentsOf: resultURL(link.sessionId)),
      let snapshot = try? Loci_Chat_StreamEvent(serializedBytes: data)
    else { return nil }
    return SearchState.restored(link: link, result: snapshot.complete.result, text: snapshot.message)
  }
}

nonisolated extension SearchState {
  /// A finished search rebuilt from a saved or server-side `AiCityResponse`.
  static func restored(link: SessionLink, result: Loci_Chat_AiCityResponse, text: String = "") -> SearchState {
    var state = SearchState()
    state.sessionId = link.sessionId
    state.destination = link.destination
    state.domain = link.domain
    state.cityName = link.cityName ?? (result.generalCityData.city.isEmpty ? nil : result.generalCityData.city)
    state.text = text
    state.status = .completed
    if result.hasGeneralCityData { state.cityData = result.generalCityData }
    state.adopt(result)
    // A phone copy saved before proto v5.22 kept a list in points_of_interest.
    switch link.destination {
    case .itinerary: break
    case .hotels: if state.hotels.isEmpty { state.hotels = result.pointsOfInterest }
    case .restaurants: if state.restaurants.isEmpty { state.restaurants = result.pointsOfInterest }
    case .activities: if state.activities.isEmpty { state.activities = result.pointsOfInterest }
    }
    return state
  }
}
