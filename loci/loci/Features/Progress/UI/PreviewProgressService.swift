import Foundation
import LociConnectProto
import SwiftProtobuf

/// Offline sample data for `-designPreview leaderboard`, `myProgress` and the
/// profile's rank line: a week where five people you follow are close.
nonisolated struct PreviewProgressService: ProgressService {
  func progress() async throws -> Loci_Gamification_Progress { .preview }

  func fieldProfile() async throws -> Loci_Gamification_FieldProfile {
    var field = Loci_Gamification_FieldProfile()
    field.lifetimeScore = 385
    field.overallRank = .walker
    field.overallNextThreshold = 600
    field.weekScore = 46
    field.lastWeekScore = 38
    field.weekStreak.current = 3
    field.weekStreak.longest = 5
    field.weekStreak.exploredThisWeek = true
    return field
  }

  func board(metric: Loci_Gamification_FieldBoardMetric) async throws -> Loci_Gamification_GetFieldBoardResponse {
    struct Row {
      let username: String
      let name: String
      let score: Int64
      let rank: Loci_Gamification_FieldRank
      var isMe = false
    }
    let rows = [
      Row(username: "ana", name: "Ana Ribeiro", score: 62, rank: .guide),
      Row(username: "me", name: "You", score: 46, rank: .walker, isMe: true),
      Row(username: "tomas", name: "Tomás Lima", score: 31, rank: .walker),
      Row(username: "joana", name: "Joana Costa", score: 25, rank: .scout),
      Row(username: "marco", name: "Marco Bianchi", score: 12, rank: .scout),
    ]
    let scale: Int64 = metric == .overall ? 1 : 8
    var response = Loci_Gamification_GetFieldBoardResponse()
    response.scope = .friendsWeek
    response.friendsAvailable = true
    response.scoredUsers = Int32(rows.count)
    response.top = rows.enumerated().map { offset, row in
      var entry = Loci_Gamification_FieldBoardRow()
      entry.user.id = "preview-\(row.username)"
      entry.user.username = row.username
      entry.user.displayName = row.name
      entry.user.homeCity = "Lisbon"
      entry.displayName = row.name
      entry.position = Int32(offset + 1)
      entry.value = max(row.score / scale, 1)
      entry.rank = row.rank
      entry.isMe = row.isMe
      return entry
    }
    return response
  }

  func history(pageToken: String) async throws -> Loci_Gamification_ListPointsHistoryResponse {
    struct Item {
      let label: String
      let points: Int32
      let ago: TimeInterval
    }
    let items = [
      Item(label: "Visited Pantheon", points: 10, ago: 1800),
      Item(label: "Walked Rome on foot, day 2", points: 20, ago: 3600 * 5),
      Item(label: "New city: Rome", points: 50, ago: 86_400),
      Item(label: "Daily check-in", points: 5, ago: 86_400 + 600),
      Item(label: "Scout report confirmed", points: 15, ago: 86_400 * 2),
    ]
    var response = Loci_Gamification_ListPointsHistoryResponse()
    response.events = items.enumerated().map { offset, item in
      var event = Loci_Gamification_PointsEvent()
      event.id = "preview-event-\(offset)"
      event.label = item.label
      event.points = item.points
      event.createdAt = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(-item.ago))
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
    let all = [
      ["first-city", "First city", "Visit your first city with Loci."],
      ["globetrotter", "Globetrotter", "Visit 10 cities."],
      ["trailblazer", "Trailblazer", "Visit 50 places on the spot."],
      ["streak-7", "Week streak", "Open Loci 7 days in a row."],
      ["streak-30", "Month streak", "Open Loci 30 days in a row."],
      ["trip-finisher", "Trip finisher", "Walk every day of a trip."],
      ["local-scout", "Local scout", "Have 10 field reports confirmed."],
    ]
    let threeDaysAgo = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(-86_400 * 3))
    progress.badges = all.map { fields in
      var badge = Loci_Gamification_Badge()
      badge.id = fields[0]
      badge.title = fields[1]
      badge.description_p = fields[2]
      if earned.contains(fields[0]) { badge.awardedAt = threeDaysAgo }
      return badge
    }
    return progress
  }
}
