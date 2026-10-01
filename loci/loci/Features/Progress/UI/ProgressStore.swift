import LociConnectProto
import Observation

/// Progress and the friends leaderboard (web: /friends Progress and
/// Leaderboard cards).
@MainActor @Observable final class ProgressStore {
  enum Phase: Equatable {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var phase = Phase.loading
  private(set) var progress: Loci_Gamification_Progress?
  private(set) var entries: [Loci_Gamification_LeaderboardEntry] = []
  private(set) var events: [Loci_Gamification_PointsEvent] = []
  private(set) var nextPageToken = ""
  var period = Loci_Gamification_LeaderboardPeriod.week
  var metric = Loci_Gamification_LeaderboardMetric.points

  private let service: any ProgressService

  init(service: any ProgressService = ConnectProgressService()) {
    self.service = service
  }

  /// Only the caller on the board: nobody to compete with yet.
  var isAlone: Bool { entries.count <= 1 }
  var me: Loci_Gamification_LeaderboardEntry? { entries.first(where: \.isMe) }

  func load() async {
    do {
      async let progress = service.progress()
      async let board = service.leaderboard(period: period, metric: metric)
      async let history = service.history(pageToken: "")
      let (p, b, h) = try await (progress, board, history)
      self.progress = p
      entries = b.entries
      events = h.events
      nextPageToken = h.nextPageToken
      phase = .loaded
    } catch {
      if progress == nil { phase = .failed(error.userMessage) }
    }
  }

  func reloadBoard() async {
    do {
      entries = try await service.leaderboard(period: period, metric: metric).entries
    } catch {
      phase = .failed(error.userMessage)
    }
  }

  func loadMoreHistory() async {
    guard !nextPageToken.isEmpty else { return }
    if let page = try? await service.history(pageToken: nextPageToken) {
      events += page.events
      nextPageToken = page.nextPageToken
    }
  }
}
