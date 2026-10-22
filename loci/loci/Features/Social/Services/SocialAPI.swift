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

  /// Loci users among the Facebook friends the caller's link granted.
  static func facebookFriends() async throws -> [Loci_Social_UserResult] {
    try await rpc("Could not find your Facebook friends.", Loci_Social_MatchFacebookFriendsRequest()) {
      await client.matchFacebookFriends(request: $0, headers: [:])
    }.matches
  }

  // MARK: Follows

  static func follow(userID: String) async throws -> FollowEdge {
    var request = Loci_Social_FollowUserRequest()
    request.target = .userID(userID)
    let response = try await rpc("Could not follow.", request) { await client.follow(request: $0, headers: [:]) }
    return FollowEdge(state: response.followState, followsYou: response.followsYou)
  }

  /// Also withdraws a request still waiting on a private account.
  static func unfollow(userID: String) async throws {
    var request = Loci_Social_UnfollowRequest()
    request.userID = userID
    _ = try await rpc("Could not unfollow.", request) { await client.unfollow(request: $0, headers: [:]) }
  }

  static func removeFollower(userID: String) async throws {
    var request = Loci_Social_RemoveFollowerRequest()
    request.userID = userID
    _ = try await rpc("Could not remove the follower.", request) { await client.removeFollower(request: $0, headers: [:]) }
  }

  /// Someone's followers; the caller's own when `userID` is empty.
  static func followers(userID: String = "", pageToken: String = "") async throws -> Loci_Social_ListFollowsResponse {
    var request = Loci_Social_ListFollowersRequest()
    request.userID = userID
    request.pageSize = 50
    request.pageToken = pageToken
    return try await rpc("Could not load the followers.", request) { await client.listFollowers(request: $0, headers: [:]) }
  }

  /// Who someone follows; the caller's own when `userID` is empty.
  static func following(userID: String = "", pageToken: String = "") async throws -> Loci_Social_ListFollowsResponse {
    var request = Loci_Social_ListFollowingRequest()
    request.userID = userID
    request.pageSize = 50
    request.pageToken = pageToken
    return try await rpc("Could not load who they follow.", request) { await client.listFollowing(request: $0, headers: [:]) }
  }

  static func followRequests(incoming: Bool) async throws -> [Loci_Social_FollowRequestEntry] {
    var request = Loci_Social_ListFollowRequestsRequest()
    request.direction = Loci_Social_RequestDirection(rawValue: incoming ? 1 : 2) ?? .unspecified
    return try await rpc("Could not load follow requests.", request) { await client.listFollowRequests(request: $0, headers: [:]) }.requests
  }

  static func respondFollow(requestID: String, approve: Bool) async throws {
    var request = Loci_Social_RespondFollowRequestRequest()
    request.requestID = requestID
    request.approve = approve
    _ = try await rpc("Could not answer the request.", request) { await client.respondFollowRequest(request: $0, headers: [:]) }
  }

  static func cancelFollow(requestID: String) async throws {
    var request = Loci_Social_CancelFollowRequestRequest()
    request.requestID = requestID
    _ = try await rpc("Could not cancel the request.", request) { await client.cancelFollowRequest(request: $0, headers: [:]) }
  }

  static func socialSettings() async throws -> Loci_Social_SocialSettings {
    try await rpc("Could not load your privacy setting.", Loci_Social_GetSocialSettingsRequest()) {
      await client.getSocialSettings(request: $0, headers: [:])
    }.settings
  }

  static func setPrivate(_ isPrivate: Bool) async throws -> Loci_Social_SocialSettings {
    var request = Loci_Social_SetAccountPrivacyRequest()
    request.isPrivate = isPrivate
    return try await rpc("Could not change your privacy setting.", request) { await client.setAccountPrivacy(request: $0, headers: [:]) }.settings
  }

  // MARK: Feed

  static func feed(pageToken: String = "") async throws -> Loci_Social_ListFeedResponse {
    var request = Loci_Social_ListFeedRequest()
    request.pageSize = 30
    request.pageToken = pageToken
    return try await rpc("Could not load the feed.", request) { await client.listFeed(request: $0, headers: [:]) }
  }

  static func cheer(itemID: String, _ on: Bool) async throws -> Loci_Social_CheerResponse {
    if on {
      var request = Loci_Social_CheerRequest()
      request.itemID = itemID
      return try await rpc("Could not cheer.", request) { await client.cheer(request: $0, headers: [:]) }
    }
    var request = Loci_Social_UncheerRequest()
    request.itemID = itemID
    return try await rpc("Could not take the cheer back.", request) { await client.uncheer(request: $0, headers: [:]) }
  }

  // MARK: Invites

  static func myInvite() async throws -> Loci_Social_Invite {
    try await rpc("Could not load your invite.", Loci_Social_GetMyInviteRequest()) { await client.getMyInvite(request: $0, headers: [:]) }.invite
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
