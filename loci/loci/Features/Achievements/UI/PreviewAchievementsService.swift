import Foundation
import LociConnectProto
import SwiftProtobuf

/// Offline sample data for `-designPreview achievements`: a few tracks part
/// way up, two moments, a hidden secret, and a pending reveal.
nonisolated struct PreviewAchievementsService: AchievementsService {
  var reveals = true

  func list(userID: String) async throws -> Loci_Gamification_ListAchievementsResponse {
    var response = Loci_Gamification_ListAchievementsResponse()
    response.achievements = Self.sample
    response.earnedCount = Int32(Self.sample.filter(\.isEarned).count)
    response.total = 79
    response.unseenBackfillCount = reveals && userID.isEmpty ? Int32(Self.sample.filter { $0.isNew }.count) : 0
    return response
  }

  func markSeen(_ ids: [String]) async throws {}

  static var sample: [Loci_Achievement_Achievement] {
    let weekAgo = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(-86_400 * 7))
    func track(_ id: String, _ title: String, _ blurb: String, _ icon: String, thresholds: [Int64], progress: Int64, rarity: Float?)
      -> Loci_Achievement_Achievement
    {
      var a = Loci_Achievement_Achievement()
      a.id = id
      a.title = title
      a.description_p = blurb
      a.icon = icon
      a.kind = .track
      a.progress = progress
      a.steps = thresholds.enumerated().map { index, threshold in
        var step = Loci_Achievement_TierStep()
        step.tier = Loci_Achievement_AchievementTier(rawValue: index + 1) ?? .unspecified
        step.threshold = threshold
        if progress >= threshold { step.earnedAt = weekAgo }
        return step
      }
      let reached = thresholds.filter { progress >= $0 }.count
      a.tier = Loci_Achievement_AchievementTier(rawValue: reached) ?? .unspecified
      a.nextTarget = thresholds.first { progress < $0 } ?? 0
      if reached > 0 {
        a.earnedAt = weekAgo
        a.isNew = true
      }
      if let rarity { a.rarityPct = rarity }
      return a
    }
    func one(_ id: String, _ title: String, _ blurb: String, _ icon: String, kind: Loci_Achievement_AchievementKind, earned: Bool)
      -> Loci_Achievement_Achievement
    {
      var a = Loci_Achievement_Achievement()
      a.id = id
      a.title = title
      a.description_p = blurb
      a.icon = icon
      a.kind = kind
      a.hidden = kind == .secret && !earned
      a.nextTarget = earned ? 0 : 1
      if earned { a.earnedAt = weekAgo }
      return a
    }
    return [
      track("cartographer", "Cartographer", "Explore new cities.", "map", thresholds: [5, 15, 30, 50], progress: 17, rarity: 12),
      track("border-crosser", "Border Crosser", "Explore new countries.", "globe", thresholds: [2, 5, 10, 20], progress: 4, rarity: 31),
      track("footfall", "Footfall", "Places visited on the spot.", "footprints", thresholds: [25, 100, 300, 750], progress: 61, rarity: 18),
      track("field-notes", "Field Notes", "Diary entries on your trip days.", "notebook-pen", thresholds: [3, 15, 40, 100], progress: 1, rarity: nil),
      track("steady-boots", "Steady Boots", "Weeks in a row you explored.", "flame", thresholds: [4, 12, 26, 52], progress: 13, rarity: 0.6),
      one("first-pin", "First Pin", "Your first city.", "map-pin", kind: .moment, earned: true),
      one("round-trip", "Round Trip", "Finish a trip.", "repeat", kind: .moment, earned: false),
      one("night-owl", "Night Owl", "Out exploring after midnight.", "moon", kind: .secret, earned: false),
    ]
  }
}
