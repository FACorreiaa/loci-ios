import Connect
import Foundation
import LociConnectProto

/// LocalContextService calls that are not the results-page context
/// (`ResultsAPI.localContext`/`fxRates`) or the here-brief (`HereBriefModel`).
nonisolated enum LocalContextAPI {
  /// web: useGoScore{lat, lon}. The server names the city it scored.
  static func goScore(latitude: Double, longitude: Double) async throws -> (score: Loci_Localcontext_GoScore, cityName: String)? {
    var request = Loci_Localcontext_GetGoScoreRequest()
    request.latitude = latitude
    request.longitude = longitude
    let response = try await rpc("Could not work out a GoScore.", request) {
      await SettingsClients.localContext.getGoScore(request: $0, headers: [:])
    }
    guard response.hasScore else { return nil }
    return (response.score, response.cityName)
  }

  /// web: useDriveCost(distanceKm). No currency: the server picks from the account.
  static func driveCost(km: Double) async throws -> Loci_Localcontext_DriveCostEstimate? {
    var request = Loci_Localcontext_EstimateDriveCostRequest()
    request.distanceKm = km
    let response = try await rpc("Could not estimate fuel.", request) {
      await SettingsClients.localContext.estimateDriveCost(request: $0, headers: [:])
    }
    return response.hasEstimate ? response.estimate : nil
  }
}
