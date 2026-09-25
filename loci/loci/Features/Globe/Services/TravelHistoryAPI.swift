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
}

/// What the globe needs from the server, behind a protocol so the design
/// previews and tests run without a session.
nonisolated protocol TravelHistoryService: Sendable { func globeData() async throws -> GlobeData }

nonisolated struct ConnectTravelHistoryService: TravelHistoryService {
  func globeData() async throws -> GlobeData { try await TravelHistoryAPI.globeData() }
}
