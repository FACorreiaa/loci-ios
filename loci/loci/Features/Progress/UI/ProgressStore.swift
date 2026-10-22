import LociConnectProto
import Observation

/// The Field score and the Following board (web: /field): rank, this week,
/// the weekly streak, where the points came from, and you against who you follow.
@MainActor @Observable final class ProgressStore {
  enum Phase: Equatable {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var phase = Phase.loading
  private(set) var progress: Loci_Gamification_Progress?
  private(set) var field: Loci_Gamification_FieldProfile?
  private(set) var board: Loci_Gamification_GetFieldBoardResponse?
  private(set) var events: [Loci_Gamification_PointsEvent] = []
  private(set) var nextPageToken = ""
  var metric = Loci_Gamification_FieldBoardMetric.overall
  /// A failed refresh or "Show more" once something is on screen.
  var error: String?

  private let service: any ProgressService

  init(service: any ProgressService = ConnectProgressService()) {
    self.service = service
  }

  /// The board's rows: the top, then the one just above you and you when
  /// you're outside it (the server sends those apart).
  var rows: [Loci_Gamification_FieldBoardRow] {
    guard let board else { return [] }
    var rows = board.top
    for extra in [board.hasAbove ? board.above : nil, board.hasMe ? board.me : nil].compactMap({ $0 })
    where !rows.contains(where: { $0.position == extra.position && $0.isMe == extra.isMe }) {
      rows.append(extra)
    }
    return rows
  }

  /// Nobody followed yet: nobody to compete with.
  var isAlone: Bool { board.map { !$0.friendsAvailable } ?? false }

  func load() async {
    do {
      async let progress = service.progress()
      async let field = service.fieldProfile()
      async let history = service.history(pageToken: "")
      let (p, f, h) = try await (progress, field, history)
      self.progress = p
      self.field = f
      events = h.events
      nextPageToken = h.nextPageToken
      phase = .loaded
    } catch {
      guard !error.isCancellation else { return }
      if field == nil { phase = .failed(error.userMessage) } else { self.error = error.userMessage }
    }
  }

  func loadBoard() async {
    do {
      board = try await service.board(metric: metric)
      phase = .loaded
    } catch {
      // A newer metric cancelled this one; its own reload follows.
      guard !error.isCancellation else { return }
      if board == nil { phase = .failed(error.userMessage) } else { self.error = error.userMessage }
    }
  }

  func loadMoreHistory() async {
    guard !nextPageToken.isEmpty else { return }
    do {
      let page = try await service.history(pageToken: nextPageToken)
      events += page.events
      nextPageToken = page.nextPageToken
    } catch {
      if !error.isCancellation { self.error = error.userMessage }
    }
  }
}
