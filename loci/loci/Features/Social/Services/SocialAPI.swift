import Foundation
import LociConnectProto

/// SocialService (loci.social) plus TripService's sharing RPCs, web:
/// lib/api/social.ts and the sharing hooks in lib/api/trips.ts.
nonisolated enum SocialAPI {
  private static let client = Loci_Social_SocialServiceClient(client: ConnectTransport.shared.protocolClient)
  private static var trips: Loci_Trip_TripServiceClient { TripAPI.client }

  private static func firstPage() -> Loci_Common_PaginationRequest {
    var page = Loci_Common_PaginationRequest()
    page.page = 1
    page.pageSize = 50
    return page
  }

  // MARK: Friends

  static func friends() async throws -> [Loci_Social_Friend] {
    try await rpc("Could not load your friends.", Loci_Social_ListFriendsRequest()) { await client.listFriends(request: $0, headers: [:]) }.friends
  }

  static func requests(incoming: Bool) async throws -> [Loci_Social_FriendRequest] {
    var request = Loci_Social_ListFriendRequestsRequest()
    request.direction = Loci_Social_RequestDirection(rawValue: incoming ? 1 : 2) ?? .unspecified
    return try await rpc("Could not load friend requests.", request) { await client.listFriendRequests(request: $0, headers: [:]) }.requests
  }

  static func sendRequest(userID: String) async throws -> Relationship {
    var request = Loci_Social_SendFriendRequestRequest()
    request.target = .userID(userID)
    let response = try await rpc("Could not send the request.", request) { await client.sendFriendRequest(request: $0, headers: [:]) }
    return Relationship(response.relationship)
  }

  static func respond(requestID: String, accept: Bool) async throws {
    var request = Loci_Social_RespondFriendRequestRequest()
    request.requestID = requestID
    request.accept = accept
    _ = try await rpc("Could not answer the request.", request) { await client.respondFriendRequest(request: $0, headers: [:]) }
  }

  static func cancel(requestID: String) async throws {
    var request = Loci_Social_CancelFriendRequestRequest()
    request.requestID = requestID
    _ = try await rpc("Could not cancel the request.", request) { await client.cancelFriendRequest(request: $0, headers: [:]) }
  }

  static func remove(userID: String) async throws {
    var request = Loci_Social_RemoveFriendRequest()
    request.userID = userID
    _ = try await rpc("Could not remove your friend.", request) { await client.removeFriend(request: $0, headers: [:]) }
  }

  static func block(userID: String) async throws {
    var request = Loci_Social_BlockUserRequest()
    request.userID = userID
    _ = try await rpc("Could not block.", request) { await client.blockUser(request: $0, headers: [:]) }
  }

  static func unblock(userID: String) async throws {
    var request = Loci_Social_UnblockUserRequest()
    request.userID = userID
    _ = try await rpc("Could not unblock.", request) { await client.unblockUser(request: $0, headers: [:]) }
  }

  // MARK: Invites

  static func myInvite() async throws -> Loci_Social_Invite {
    try await rpc("Could not load your invite.", Loci_Social_GetMyInviteRequest()) { await client.getMyInvite(request: $0, headers: [:]) }.invite
  }

  static func rotateInvite() async throws -> Loci_Social_Invite {
    try await rpc("Could not make a new link.", Loci_Social_RotateInviteRequest()) { await client.rotateInvite(request: $0, headers: [:]) }.invite
  }

  static func invite(code: String) async throws -> Loci_Social_GetInviteResponse {
    var request = Loci_Social_GetInviteRequest()
    request.code = code
    return try await rpc("This invite has expired.", request) { await client.getInvite(request: $0, headers: [:]) }
  }

  static func acceptInvite(code: String) async throws -> Loci_Social_PublicUser {
    var request = Loci_Social_AcceptInviteRequest()
    request.code = code
    return try await rpc("Could not accept the invite.", request) { await client.acceptInvite(request: $0, headers: [:]) }.friend.user
  }

  // MARK: Finding people

  static func matchContacts(hashes: [String]) async throws -> [Loci_Social_ContactMatch] {
    var request = Loci_Social_MatchContactsRequest()
    request.hashes = Array(hashes.prefix(2000))
    return try await rpc("Could not check your contacts.", request) { await client.matchContacts(request: $0, headers: [:]) }.matches
  }

  static func search(_ query: String) async throws -> [Loci_Social_UserResult] {
    var request = Loci_Social_SearchUsersRequest()
    request.query = query
    request.limit = 20
    return try await rpc("Could not search.", request) { await client.searchUsers(request: $0, headers: [:]) }.users
  }

  static func profile(username: String) async throws -> Loci_Social_GetPublicProfileResponse {
    var request = Loci_Social_GetPublicProfileRequest()
    request.target = .username(username)
    return try await rpc("No traveller by that name.", request) { await client.getPublicProfile(request: $0, headers: [:]) }
  }

  // MARK: Trips

  static func friendTrips() async throws -> [Loci_Trip_TripDraft] {
    var request = Loci_Trip_ListFriendTripsRequest()
    request.pagination = firstPage()
    return try await rpc("Could not load your friends' trips.", request) { await trips.listFriendTrips(request: $0, headers: [:]) }.trips
  }

  static func userTrips(userID: String) async throws -> [Loci_Trip_TripDraft] {
    var request = Loci_Trip_ListUserTripsRequest()
    request.userID = userID
    request.pagination = firstPage()
    return try await rpc("Could not load their trips.", request) { await trips.listUserTrips(request: $0, headers: [:]) }.trips
  }

  static func sharedTrip(code: String) async throws -> Loci_Trip_TripDraft {
    var request = Loci_Trip_GetSharedTripRequest()
    request.shareCode = code
    return try await rpc("This trip isn't shared any more.", request) { await trips.getSharedTrip(request: $0, headers: [:]) }
  }

  static func friendTrip(id: String) async throws -> Loci_Trip_TripDraft {
    var request = Loci_Trip_GetFriendTripRequest()
    request.tripID = id
    return try await rpc("You can't see this trip.", request) { await trips.getFriendTrip(request: $0, headers: [:]) }
  }

  /// Saves a trip the caller may see as their own, private; returns its id.
  static func copy(_ source: SharedTripSource) async throws -> String {
    var request = Loci_Trip_CopyTripRequest()
    switch source {
    case .code(let code): request.source = .shareCode(code)
    case .tripID(let id): request.source = .tripID(id)
    }
    return try await rpc("Could not copy the trip.", request) { await trips.copyTrip(request: $0, headers: [:]) }.tripID
  }

  static func setVisibility(tripID: String, _ visibility: TripVisibility) async throws -> Loci_Trip_SetTripVisibilityResponse {
    var request = Loci_Trip_SetTripVisibilityRequest()
    request.tripID = tripID
    request.visibility = visibility.proto
    return try await rpc("Could not change who can see this trip.", request) { await trips.setTripVisibility(request: $0, headers: [:]) }
  }
}

/// How a shared trip was reached: its link, or its id (a friend's trip).
nonisolated enum SharedTripSource: Hashable, Sendable {
  case code(String)
  case tripID(String)
}
