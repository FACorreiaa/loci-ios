import Foundation
import LociConnectProto

/// What the progress and leaderboard screens read, so design previews can
/// show them without a server.
protocol ProgressService: Sendable {
  func progress() async throws -> Loci_Gamification_Progress
  func leaderboard(period: Loci_Gamification_LeaderboardPeriod, metric: Loci_Gamification_LeaderboardMetric) async throws
    -> Loci_Gamification_GetLeaderboardResponse
  func history(pageToken: String) async throws -> Loci_Gamification_ListPointsHistoryResponse
}

nonisolated struct ConnectProgressService: ProgressService {
  func progress() async throws -> Loci_Gamification_Progress { try await ProgressAPI.progress() }

  func leaderboard(period: Loci_Gamification_LeaderboardPeriod, metric: Loci_Gamification_LeaderboardMetric) async throws
    -> Loci_Gamification_GetLeaderboardResponse
  {
    try await ProgressAPI.leaderboard(period: period, metric: metric)
  }

  func history(pageToken: String) async throws -> Loci_Gamification_ListPointsHistoryResponse {
    try await ProgressAPI.history(pageToken: pageToken)
  }
}

extension Loci_Gamification_Progress {
  /// How far into the current level the total is, 0…1.
  var levelFraction: Double {
    let span = Double(Self.threshold(Int(level) + 1) - Self.threshold(Int(level)))
    guard span > 0 else { return 0 }
    return min(max(1 - Double(pointsToNextLevel) / span, 0), 1)
  }

  /// Level L starts at 50·L·(L−1) points (server: gamification.LevelFor).
  static func threshold(_ level: Int) -> Int64 { 50 * Int64(level) * Int64(level - 1) }

  var earnedBadges: [Loci_Gamification_Badge] { badges.filter(\.hasAwardedAt) }
}

extension Loci_Gamification_LeaderboardMetric {
  var title: String {
    switch self {
    case .cities: "Cities"
    case .places: "Places"
    default: "Points"
    }
  }

  func format(_ value: Int64) -> String {
    switch self {
    case .cities: value == 1 ? "1 city" : "\(value) cities"
    case .places: value == 1 ? "1 place" : "\(value) places"
    default: "\(value.formatted()) pts"
    }
  }
}

extension Loci_Gamification_LeaderboardPeriod {
  var title: String {
    switch self {
    case .month: "Month"
    case .allTime: "All time"
    default: "Week"
    }
  }
}
