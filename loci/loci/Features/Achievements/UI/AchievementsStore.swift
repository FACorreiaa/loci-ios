import LociConnectProto
import Observation

/// Someone's achievements (web: /achievements): the catalogue with progress,
/// grouped and filtered, and the one-time reveal of what the backfill found.
@MainActor @Observable final class AchievementsStore {
  enum Phase: Equatable {
    case loading
    case loaded
    case failed(String)
  }

  enum Filter: String, CaseIterable, Identifiable {
    case all = "All"
    case earned = "Earned"
    case next = "Up next"

    var id: Self { self }
  }

  private(set) var phase = Phase.loading
  private(set) var achievements: [Loci_Achievement_Achievement] = []
  private(set) var earnedCount = 0
  private(set) var total = 0
  /// Earned before the feature shipped and never shown: the reveal's count.
  private(set) var unseenBackfill = 0
  var filter = Filter.all
  var error: String?

  /// Empty for the caller's own.
  let userID: String
  private let service: any AchievementsService
  private var markedSeen = false

  init(userID: String = "", service: any AchievementsService = ConnectAchievementsService()) {
    self.userID = userID
    self.service = service
  }

  var isOwn: Bool { userID.isEmpty }

  /// What the filter shows: everything, the earned, or the unearned closest to their next rung.
  var shown: [Loci_Achievement_Achievement] {
    switch filter {
    case .all: achievements
    case .earned: achievements.filter(\.isEarned)
    case .next: achievements.filter { !$0.hidden && $0.nextTarget > 0 }.sorted { $0.closeness > $1.closeness }
    }
  }

  /// Tracks, moments and secrets, each with what the filter leaves of it.
  var groups: [(kind: AchievementKind, items: [Loci_Achievement_Achievement])] {
    [AchievementKind.track, .moment, .secret].compactMap { kind in
      let items = shown.filter { $0.kindValue == kind }
      return items.isEmpty ? nil : (kind, items)
    }
  }

  /// Earned rows not shown yet, outside the reveal (which clears its own).
  var fresh: [Loci_Achievement_Achievement] { achievements.filter { $0.isNew && !$0.hidden } }

  /// The backfilled ones the reveal lists: the earned rows still marked new.
  var revealed: [Loci_Achievement_Achievement] { achievements.filter { $0.isNew && $0.isEarned }.sorted { $0.rank > $1.rank } }

  var showsReveal: Bool { isOwn && unseenBackfill > 0 }

  func load() async {
    do {
      let response = try await service.list(userID: userID)
      achievements = response.achievements
      earnedCount = Int(response.earnedCount)
      total = Int(response.total)
      unseenBackfill = Int(response.unseenBackfillCount)
      phase = .loaded
    } catch {
      guard !error.isCancellation else { return }
      if phase == .loaded { self.error = error.userMessage } else { phase = .failed(error.userMessage) }
    }
  }

  /// Clears the "New" marks once the page has shown them. Not while the reveal
  /// is pending: it clears the backfilled ones when it closes.
  func markFreshSeen() async {
    guard isOwn, !markedSeen, unseenBackfill == 0 else { return }
    let ids = fresh.map(\.id)
    guard !ids.isEmpty else { return }
    markedSeen = true
    try? await service.markSeen(ids)
  }

  /// The reveal closed: everything it listed is seen, here and on the web.
  func dismissReveal() async {
    let ids = achievements.filter(\.isNew).map(\.id)
    unseenBackfill = 0
    for index in achievements.indices { achievements[index].isNew = false }
    guard !ids.isEmpty else { return }
    try? await service.markSeen(ids)
  }
}
