import Foundation
import LociConnectProto

/// BundleService (loci.bundle.v1), one static func per RPC (web: lib/api/bundles.ts).
///
/// `CreateBundleCheckout` is deliberately absent and must stay so: iOS does not
/// sell packs (App Store 3.1.1). A paid pack the caller does not own is shown
/// locked, with no price and no way to buy it from the app.
nonisolated enum PacksAPI {
  private static let client = Loci_Bundle_V1_BundleServiceClient(client: ConnectTransport.shared.protocolClient)

  /// web: usePacks. The catalog is public on the server; the token the app
  /// always sends makes the same call report which packs the caller owns.
  static func list(_ filters: PackFilters) async throws -> PackPage {
    let response = try await rpc("Could not load the City Packs.", filters.request) { await client.listBundles(request: $0, headers: [:]) }
    return PackPage(packs: response.bundles.map(PackSummary.init), total: Int(response.pagination.totalRecords))
  }

  /// web: usePack. Only the days the caller may read come back; the rest is `lockedDayCount`.
  static func detail(slug: String) async throws -> PackDetail {
    var request = Loci_Bundle_V1_GetBundleRequest()
    request.slug = slug
    let response = try await rpc("Could not load this pack.", request) { await client.getBundle(request: $0, headers: [:]) }
    return PackDetail(response)
  }

  /// web: useClaimPack. Copies the pack into the caller's trips and returns the new trip's id.
  /// The server refuses a paid pack the caller does not own (PermissionDenied).
  static func claim(bundleId: String) async throws -> String {
    var request = Loci_Bundle_V1_ClaimBundleRequest()
    request.bundleID = bundleId
    let response = try await rpc("That did not save. Try again in a moment.", request) { await client.claimBundle(request: $0, headers: [:]) }
    return response.tripID
  }

  /// web: useMyPacks (page 1, 50). The packs this person has bought.
  static func mine() async throws -> [PackSummary] {
    var request = Loci_Bundle_V1_ListMyBundlesRequest()
    request.pagination.page = 1
    request.pagination.pageSize = 50
    let response = try await rpc("Could not load your packs.", request) { await client.listMyBundles(request: $0, headers: [:]) }
    return response.bundles.map(PackSummary.init)
  }
}

/// What the Packs screens need from the server, behind a protocol so the
/// design previews and tests run without a session.
nonisolated protocol PacksService: Sendable {
  func list(_ filters: PackFilters) async throws -> PackPage
  func detail(slug: String) async throws -> PackDetail
  /// The new trip's id.
  func claim(bundleId: String) async throws -> String
}

nonisolated struct ConnectPacksService: PacksService {
  func list(_ filters: PackFilters) async throws -> PackPage { try await PacksAPI.list(filters) }
  func detail(slug: String) async throws -> PackDetail { try await PacksAPI.detail(slug: slug) }
  func claim(bundleId: String) async throws -> String { try await PacksAPI.claim(bundleId: bundleId) }
}
