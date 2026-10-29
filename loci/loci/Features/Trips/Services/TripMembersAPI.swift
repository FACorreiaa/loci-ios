import Foundation
import LociConnectProto

/// Planning a trip together (web: lib/api/trip-members.ts): the owner's invite
/// link, its preview, joining, and leaving or removing a member.
nonisolated enum TripMembersAPI {
  private static var client: Loci_Trip_TripServiceClient { TripAPI.client }

  /// The trip's live co-planner invite, minted on first use. Owner only.
  static func invite(tripID: String) async throws -> Loci_Trip_TripInvite {
    var request = Loci_Trip_CreateTripInviteRequest()
    request.tripID = tripID
    request.role = .coPlanner
    return try await rpc("Could not make an invite link.", request) { await client.createTripInvite(request: $0, headers: [:]) }
  }

  /// What an invite link shows before joining.
  static func preview(code: String) async throws -> Loci_Trip_TripInvitePreview {
    var request = Loci_Trip_GetTripInviteRequest()
    request.code = code
    return try await rpc("This invite link doesn't open a trip.", request) { await client.getTripInvite(request: $0, headers: [:]) }
  }

  /// Joins the invite's trip; returns its id. Joining again is harmless.
  static func accept(code: String) async throws -> String {
    var request = Loci_Trip_AcceptTripInviteRequest()
    request.code = code
    return try await rpc("Couldn't join the trip. The invite may have just expired.", request) {
      await client.acceptTripInvite(request: $0, headers: [:])
    }.tripID
  }

  /// Whether co-planners may apply suggestions too. Owner only; answers the
  /// rule as saved.
  static func setCoPlannersMayApply(tripID: String, _ may: Bool) async throws -> Bool {
    var request = Loci_Trip_SetTripPlanningRulesRequest()
    request.tripID = tripID
    request.coPlannersMayApply = may
    return try await rpc("Couldn't change that setting.", request) {
      await client.setTripPlanningRules(request: $0, headers: [:])
    }.coPlannersMayApply
  }

  /// The owner removes anyone; a member removes only themselves.
  static func remove(tripID: String, userID: String) async throws {
    var request = Loci_Trip_RemoveTripMemberRequest()
    request.tripID = tripID
    request.userID = userID
    _ = try await rpc("Could not leave the trip.", request) { await client.removeTripMember(request: $0, headers: [:]) }
  }
}
