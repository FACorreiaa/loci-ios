import Foundation
import LociConnectProto

/// What the progress and leaderboard screens read, so design previews can
/// show them without a server.
protocol ProgressService: Sendable {
  func progress() async throws -> Loci_Gamification_Progress
  func fieldProfile() async throws -> Loci_Gamification_FieldProfile
  func board(metric: Loci_Gamification_FieldBoardMetric) async throws -> Loci_Gamification_GetFieldBoardResponse
  func history(pageToken: String) async throws -> Loci_Gamification_ListPointsHistoryResponse
}

nonisolated struct ConnectProgressService: ProgressService {
  func progress() async throws -> Loci_Gamification_Progress { try await ProgressAPI.progress() }

  func fieldProfile() async throws -> Loci_Gamification_FieldProfile { try await ProgressAPI.fieldProfile() }

  /// The Following board: you and who you follow, this week.
  func board(metric: Loci_Gamification_FieldBoardMetric) async throws -> Loci_Gamification_GetFieldBoardResponse {
    try await ProgressAPI.fieldBoard(scope: .friendsWeek, metric: metric)
  }

  func history(pageToken: String) async throws -> Loci_Gamification_ListPointsHistoryResponse {
    try await ProgressAPI.history(pageToken: pageToken)
  }
}

/// The Field ranks, Scout to Keeper (web: routes/field RANK_ORDER).
nonisolated extension Loci_Gamification_FieldRank {
  var title: String {
    switch self {
    case .walker: "Walker"
    case .guide: "Guide"
    case .local: "Local"
    case .keeper: "Keeper"
    default: "Scout"
    }
  }

  /// The rank after this one; nil at Keeper.
  var next: Self? {
    switch self {
    case .walker: .guide
    case .guide: .local
    case .local: .keeper
    case .keeper: nil
    default: .walker
    }
  }
}

nonisolated extension Loci_Gamification_FieldProfile {
  /// 0…1 of the way from 0 to the next rank's threshold; 1 at Keeper.
  var rankFraction: Double {
    guard overallNextThreshold > 0 else { return 1 }
    return min(max(Double(lifetimeScore) / Double(overallNextThreshold), 0), 1)
  }
}

nonisolated extension Loci_Gamification_WeekStreak {
  /// "3 weeks in a row · explore this week to keep it" (web: weekStreakLine).
  var line: String {
    guard current > 0 else { return "Explore this week to start a streak" }
    let weeks = current == 1 ? "1 week in a row" : "\(current) weeks in a row"
    return exploredThisWeek ? weeks : "\(weeks) · explore this week to keep it"
  }
}

nonisolated extension Loci_Gamification_FieldBoardMetric {
  var title: String {
    switch self {
    case .placesKept: "Places kept"
    case .daysFinished: "Days finished"
    default: "Overall"
    }
  }

  func format(_ value: Int64) -> String {
    switch self {
    case .placesKept: value == 1 ? "1 place" : "\(value) places"
    case .daysFinished: value == 1 ? "1 day" : "\(value) days"
    default: value.formatted()
    }
  }
}
