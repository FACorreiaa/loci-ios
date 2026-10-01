import Foundation
import LociConnectProto
import SwiftProtobuf

/// Offline sample data for `-designPreview leaderboard`, `myProgress` and the
/// profile's level line: a week where five friends are close.
nonisolated struct PreviewProgressService: ProgressService {
  func progress() async throws -> Loci_Gamification_Progress { .preview }

  func leaderboard(period: Loci_Gamification_LeaderboardPeriod, metric: Loci_Gamification_LeaderboardMetric) async throws
    -> Loci_Gamification_GetLeaderboardResponse
  {
    var response = Loci_Gamification_GetLeaderboardResponse()
    let rows: [(String, String, Int64, Int32, Int32, Bool)] = [
      ("ana", "Ana Ribeiro", 420, 6, 12, false),
      ("me", "You", 385, 5, 7, true),
      ("tomas", "Tomás Lima", 310, 5, 3, false),
      ("joana", "Joana Costa", 255, 4, 0, false),
      ("marco", "Marco Bianchi", 120, 3, 1, false),
    ]
    let scale: Int64 = metric == .points ? 1 : 30
    response.entries = rows.enumerated().map { offset, row in
      var entry = Loci_Gamification_LeaderboardEntry()
      entry.user.id = "preview-\(row.0)"
      entry.user.username = row.0
      entry.user.displayName = row.1
      entry.user.homeCity = "Lisbon"
      entry.rank = Int32(offset + 1)
      entry.value = max(row.2 / scale, 1)
      entry.level = row.3
      entry.currentStreak = row.4
      entry.isMe = row.5
      return entry
    }
    return response
  }

  func history(pageToken: String) async throws -> Loci_Gamification_ListPointsHistoryResponse {
    var response = Loci_Gamification_ListPointsHistoryResponse()
    let items: [(String, Int32, Double)] = [
      ("Visited Pantheon", 10, -1800), ("Walked Rome on foot, day 2", 20, -3600 * 5),
      ("New city: Rome", 50, -86_400), ("Daily check-in", 5, -86_400 - 600), ("Scout report confirmed", 15, -86_400 * 2),
    ]
    response.events = items.enumerated().map { offset, item in
      var event = Loci_Gamification_PointsEvent()
      event.id = "preview-event-\(offset)"
      event.label = item.0
      event.points = item.1
      event.createdAt = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(item.2))
      return event
    }
    return response
  }
}

extension Loci_Gamification_Progress {
  nonisolated static var preview: Loci_Gamification_Progress {
    var progress = Loci_Gamification_Progress()
    progress.totalPoints = 385
    progress.level = 3
    progress.pointsToNextLevel = 215
    progress.currentStreak = 7
    progress.longestStreak = 9
    progress.today.checkedIn = true
    progress.today.searched = true
    progress.today.placesVisited = 2
    let earned: Set<String> = ["first-city", "streak-7", "trip-finisher"]
    let all: [(String, String, String)] = [
      ("first-city", "First city", "Visit your first city with Loci."),
      ("globetrotter", "Globetrotter", "Visit 10 cities."),
      ("trailblazer", "Trailblazer", "Visit 50 places on the spot."),
      ("streak-7", "Week streak", "Open Loci 7 days in a row."),
      ("streak-30", "Month streak", "Open Loci 30 days in a row."),
      ("trip-finisher", "Trip finisher", "Walk every day of a trip."),
      ("local-scout", "Local scout", "Have 10 field reports confirmed."),
    ]
    progress.badges = all.map { id, title, description in
      var badge = Loci_Gamification_Badge()
      badge.id = id
      badge.title = title
      badge.description_p = description
      if earned.contains(id) { badge.awardedAt = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(-86_400 * 3)) }
      return badge
    }
    return progress
  }
}
