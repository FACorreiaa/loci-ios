import Foundation
import LociConnectProto

/// GamificationService's achievement RPCs (web: lib/api/achievements.ts).
nonisolated enum AchievementsAPI {
  private static let client = Loci_Gamification_GamificationServiceClient(client: ConnectTransport.shared.protocolClient)

  /// Someone's achievements; the caller's own when `userID` is empty. Another
  /// person's private profile answers PermissionDenied.
  static func list(userID: String = "") async throws -> Loci_Gamification_ListAchievementsResponse {
    var request = Loci_Gamification_ListAchievementsRequest()
    request.userID = userID
    return try await rpc("Could not load the achievements.", request) { await client.listAchievements(request: $0, headers: [:]) }
  }

  static func markSeen(_ ids: [String]) async throws {
    var request = Loci_Gamification_MarkAchievementsSeenRequest()
    request.ids = ids
    _ = try await rpc("Could not save.", request) { await client.markAchievementsSeen(request: $0, headers: [:]) }
  }
}

/// What the achievements screens read, so design previews can show them
/// without a server.
protocol AchievementsService: Sendable {
  func list(userID: String) async throws -> Loci_Gamification_ListAchievementsResponse
  func markSeen(_ ids: [String]) async throws
}

nonisolated struct ConnectAchievementsService: AchievementsService {
  func list(userID: String) async throws -> Loci_Gamification_ListAchievementsResponse { try await AchievementsAPI.list(userID: userID) }
  func markSeen(_ ids: [String]) async throws { try await AchievementsAPI.markSeen(ids) }
}
