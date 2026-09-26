import Foundation
import LociConnectProto

/// GastronomyService (loci.gastronomy), web: lib/api/gastronomy.ts.
///
/// The server keys a city's gastronomy on the city alone and shares it with
/// the chat pipeline's gastronomy part, so after the first request for a city
/// every lookup — here, on an itinerary, or from a "food in Madeira" search —
/// is served from cache.
nonisolated enum GastronomyAPI {
  private static let client = Loci_Gastronomy_GastronomyServiceClient(client: ConnectTransport.shared.protocolClient)

  static func city(named name: String) async throws -> Loci_Gastronomy_CityGastronomy {
    var request = Loci_Gastronomy_GetCityGastronomyRequest()
    request.cityName = name
    let response = try await rpc("Could not load this city's food.", request) { await client.getCityGastronomy(request: $0, headers: [:]) }
    return response.gastronomy
  }
}

/// What the gastronomy screen needs from the server, behind a protocol so the
/// design previews and tests run without a session.
nonisolated protocol GastronomyService: Sendable {
  func city(named name: String) async throws -> Loci_Gastronomy_CityGastronomy
}

nonisolated struct ConnectGastronomyService: GastronomyService {
  func city(named name: String) async throws -> Loci_Gastronomy_CityGastronomy { try await GastronomyAPI.city(named: name) }
}
