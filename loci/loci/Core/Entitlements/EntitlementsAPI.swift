import Connect
import Foundation
import LociConnectProto

/// EntitlementService.GetEntitlements (web: fetchEntitlements). The caller
/// comes from the token; the request has no fields.
nonisolated enum EntitlementsAPI {
  private static let client = Loci_Entitlement_V1_EntitlementServiceClient(client: ConnectTransport.shared.protocolClient)

  static func fetchProto() async throws -> Loci_Entitlement_V1_Entitlements {
    try await rpc("Could not load your plan.") { await client.getEntitlements(request: .init(), headers: [:]) }
  }

  static func fetch() async throws -> Entitlements { Entitlements(try await fetchProto()) }
}
