import Foundation
import LociConnectProto

/// TravelHistoryService (loci.travelhistory), one static func per RPC
/// (web: lib/api/travel-history.ts). The server reads the caller from the
/// token; the request carries no user id.
nonisolated enum TravelHistoryAPI {
  /// web: DEFAULT_GLOBE_LIMIT / DEFAULT_PERIOD_DAYS. The limit caps cities and
  /// legs separately (the server applies it to both queries).
  static let globeLimit = 500
  static let periodDays = 365

  private static let client = Loci_Travelhistory_TravelHistoryServiceClient(client: ConnectTransport.shared.protocolClient)

  /// web: getGlobeData(500, 365). The first call for an account also runs the
  /// server's one-off backfill from earlier trips, which is what `backfilled`
  /// reports; a failed backfill is logged there and comes back as false.
  static func globeData(limit: Int = globeLimit, periodDays: Int = periodDays) async throws -> GlobeData {
    var request = Loci_Travelhistory_GetGlobeDataRequest()
    request.limit = Int32(limit)
    request.periodDays = Int32(periodDays)
    let response = try await rpc("Could not load your travels.", request) { await client.getGlobeData(request: $0, headers: [:]) }
    return GlobeMapping.data(response)
  }

  /// One page of places visited, newest first (web: useVisitedPlaces).
  static func visitedPOIs(page: Int32, pageSize: Int32 = visitedPageSize) async throws -> (pois: [Loci_Travelhistory_VisitedPOI], total: Int32) {
    var request = Loci_Travelhistory_ListVisitedPOIsRequest()
    request.page = page
    request.pageSize = pageSize
    let response = try await rpc("Could not load the places you've been.", request) { await client.listVisitedPois(request: $0, headers: [:]) }
    return (response.pois, response.total)
  }

  static let visitedPageSize: Int32 = 100

  /// "I've been here": records the place with no device fix, so it joins the
  /// traveller's history and taste without earning points.
  static func recordManualVisit(poi: Loci_Poi_POIDetailedInfo, cityName: String) async throws {
    guard let request = manualVisitRequest(poi: poi, cityName: cityName) else {
      throw APIError.custom("This place has no city or location to record.")
    }
    _ = try await rpc("Could not record the visit.", request) { await client.recordVisit(request: $0, headers: [:]) }
  }

  /// The request for a manual visit, or nil when the place lacks what the
  /// server requires: a city name and real coordinates (web: buildManualVisit).
  static func manualVisitRequest(poi: Loci_Poi_POIDetailedInfo, cityName: String) -> Loci_Travelhistory_RecordVisitRequest? {
    let city = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !city.isEmpty, poi.latitude != 0 || poi.longitude != 0 else { return nil }
    var request = Loci_Travelhistory_RecordVisitRequest()
    request.cityName = city
    request.latitude = poi.latitude
    request.longitude = poi.longitude
    if !poi.id.isEmpty { request.poiID = poi.id }
    if !poi.name.isEmpty { request.poiName = poi.name }
    return request
  }
}

/// Places I've been, behind a protocol so tests run without a session.
nonisolated protocol VisitedPlacesService: Sendable {
  func visitedPOIs(page: Int32) async throws -> (pois: [Loci_Travelhistory_VisitedPOI], total: Int32)
}

nonisolated struct ConnectVisitedPlacesService: VisitedPlacesService {
  func visitedPOIs(page: Int32) async throws -> (pois: [Loci_Travelhistory_VisitedPOI], total: Int32) {
    try await TravelHistoryAPI.visitedPOIs(page: page)
  }
}

/// What the globe needs from the server, behind a protocol so the design
/// previews and tests run without a session.
nonisolated protocol TravelHistoryService: Sendable { func globeData() async throws -> GlobeData }

nonisolated struct ConnectTravelHistoryService: TravelHistoryService {
  func globeData() async throws -> GlobeData { try await TravelHistoryAPI.globeData() }
}
