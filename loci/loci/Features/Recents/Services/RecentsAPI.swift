import Foundation
import LociConnectProto

/// RecentsService (loci.recents), one static func per RPC (web: lib/api/recents.ts).
///
/// `userId` is required non-empty by validation and ignored by the server,
/// which reads the caller from the token; iOS sends the id the session stored
/// at sign-in rather than decoding the JWT as web does.
nonisolated enum RecentsAPI {
  private static let client = Loci_Recents_RecentsServiceClient(client: ConnectTransport.shared.protocolClient)

  /// web: fetchActivityHistory. No `InteractionFilter` is ever sent: its
  /// `city_id` and `search_query` have `min_len: 1` with no ignore rule, so a
  /// filter that narrows by type only is rejected. `sortBy`/`sortOrder` are sent
  /// because older servers reject them empty.
  static func interactionHistory(userId: String, limit: Int) async throws -> ActivityPage {
    var request = Loci_Recents_GetInteractionHistoryRequest()
    request.userID = userId
    request.limit = Int32(limit)
    request.offset = 0
    request.sortBy = "date"
    request.sortOrder = "desc"
    let response = try await rpc("Could not load your activity.", request) { await client.getInteractionHistory(request: $0, headers: [:]) }
    return ActivityFeed.page(response, limit: limit)
  }

  /// web: fetchRecentInteractions(50) with `groupByCity: true`, for the Cities view.
  /// Unlike web, a failure is thrown rather than turned into an empty list.
  static func recentCities(userId: String) async throws -> [RecentCity] {
    var request = Loci_Recents_GetRecentInteractionsRequest()
    request.userID = userId
    request.limit = 50
    request.offset = 0
    request.groupByCity = true
    let response = try await rpc("Could not load your cities.", request) { await client.getRecentInteractions(request: $0, headers: [:]) }
    return RecentCities.cities(response)
  }

  /// A kept itinerary for a feed row, from the same list Saved shows
  /// (web: lib/api/itineraries.ts, page_size capped at 100).
  static func savedItinerary(id: String, sessionId: String) async throws -> Loci_Itinerary_UserSavedItinerary? {
    var request = Loci_Itinerary_GetUserItinerariesRequest()
    request.pagination.page = 1
    request.pagination.pageSize = 100
    let response = try await rpc("Could not load your saved itineraries.", request) {
      await SavedAPI.itineraries.getUserItineraries(request: $0, headers: [:])
    }
    return SavedItineraryMatch.find(in: response.itineraries, id: id, sessionId: sessionId)
  }
}

/// What the Recents screens need from the server, behind a protocol so the
/// design previews and tests run without a session.
nonisolated protocol RecentsService: Sendable {
  func activity(userId: String, pages: Int) async throws -> ActivityPage
  func cities(userId: String) async throws -> [RecentCity]
}

nonisolated struct ConnectRecentsService: RecentsService {
  func activity(userId: String, pages: Int) async throws -> ActivityPage {
    try await RecentsAPI.interactionHistory(userId: userId, limit: ActivityFeed.limit(pages: pages))
  }

  func cities(userId: String) async throws -> [RecentCity] {
    try await RecentsAPI.recentCities(userId: userId)
  }
}
