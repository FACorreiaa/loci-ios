import LociConnectProto
import SwiftUI

/// One feed of posts — a board's, or every board's when `slug` is empty — plus
/// the viewer state that decides which controls show. The server re-checks
/// every write; hiding a control is only a courtesy.
@MainActor @Observable final class BoardsFeedStore {
  enum Phase: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  let slug: String
  private(set) var board: Loci_Boards_V1_Board?
  private(set) var boards: [Loci_Boards_V1_Board] = []
  private(set) var posts: [Loci_Boards_V1_Post] = []
  private(set) var viewer = Loci_Boards_V1_GetBoardsViewerResponse()
  private(set) var phase = Phase.idle
  private(set) var nextCursor = ""
  private(set) var loadingMore = false
  var sort: Loci_Boards_V1_PostSort = .new
  var window: Loci_Boards_V1_TopWindow = .week
  var error: String?

  let service: BoardsService
  private let myIDProvider: @MainActor () -> String?
  /// The latest sort/window reload; a newer one cancels it so pages can't land out of order.
  @ObservationIgnored private var reloadTask: Task<Void, Never>?

  init(
    slug: String = "",
    service: BoardsService = ConnectBoardsService(),
    myID: @escaping @MainActor () -> String? = { AuthSessionManager.shared.currentUserID }
  ) {
    self.slug = slug
    self.service = service
    self.myIDProvider = myID
  }

  var myID: String { myIDProvider() ?? "" }
  var signedIn: Bool { viewer.signedIn || !myID.isEmpty }
  var isAdmin: Bool { viewer.isAdmin }
  var sanction: Loci_Boards_V1_Sanction? { viewer.hasActiveSanction ? viewer.activeSanction : nil }
  var canWrite: Bool { signedIn && sanction == nil }

  func isMine(_ user: Loci_Social_PublicUser) -> Bool { !myID.isEmpty && user.id == myID }

  func load() async {
    if posts.isEmpty { phase = .loading }
    async let viewerResult = try? service.viewer()
    async let boardsResult = slug.isEmpty ? try? service.boards() : nil
    async let boardResult = slug.isEmpty ? nil : try? service.board(slug: slug)
    do {
      let page = try await service.posts(board: slug, sort: sort, window: window, cursor: "")
      try Task.checkCancellation()
      posts = page.posts
      nextCursor = page.nextCursor
      phase = .loaded
    } catch {
      guard !(error is CancellationError), (error as? APIError) != .cancelled else { return }
      if posts.isEmpty { phase = .failed(error.userMessage) } else { self.error = error.userMessage }
    }
    if let v = await viewerResult { viewer = v }
    if let b = await boardsResult { boards = b }
    if let b = await boardResult { board = b }
    if !slug.isEmpty, board == nil, case .loaded = phase, posts.isEmpty {
      // The board itself failed to load: most likely deleted or mistyped.
      phase = .failed("No board here. It may have been closed.")
    }
  }

  func loadMore() async {
    guard !nextCursor.isEmpty, !loadingMore else { return }
    loadingMore = true
    defer { loadingMore = false }
    do {
      let page = try await service.posts(board: slug, sort: sort, window: window, cursor: nextCursor)
      let seen = Set(posts.map(\.id))
      posts += page.posts.filter { !seen.contains($0.id) }
      nextCursor = page.nextCursor
    } catch { self.error = error.userMessage }
  }

  /// Shows the vote at once; puts it back and explains when the server refuses.
  func vote(_ post: Loci_Boards_V1_Post, pressed: Int32) async {
    guard signedIn else {
      error = "Sign in to vote."
      return
    }
    guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
    let before = posts[index]
    let next = BoardsModel.applyVote(score: before.score, myVote: before.myVote, pressed: pressed)
    posts[index].score = next.score
    posts[index].myVote = next.myVote
    do {
      let result = try await service.vote(postID: post.id, value: next.myVote)
      if let i = posts.firstIndex(where: { $0.id == post.id }) {
        posts[i].score = result.score
        posts[i].myVote = result.myVote
      }
    } catch {
      if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i] = before }
      self.error = error.userMessage
    }
  }

  func delete(_ post: Loci_Boards_V1_Post) async {
    do { try await removePost(post) } catch { self.error = error.userMessage }
  }

  /// Deletes on the server and drops the row; the caller reports a failure.
  func removePost(_ post: Loci_Boards_V1_Post) async throws {
    try await service.deletePost(id: post.id)
    posts.removeAll { $0.id == post.id }
  }

  /// Admin: closes this board. True when it is gone.
  func deleteBoard() async -> Bool {
    do {
      try await service.deleteBoard(slug: slug)
      return true
    } catch {
      self.error = error.userMessage
      return false
    }
  }

  func reload(sort: Loci_Boards_V1_PostSort? = nil, window: Loci_Boards_V1_TopWindow? = nil) async {
    if let sort { self.sort = sort }
    if let window { self.window = window }
    reloadTask?.cancel()
    posts = []
    let task = Task { await load() }
    reloadTask = task
    await task.value
  }
}

/// A post and its comment thread.
@MainActor @Observable final class BoardPostStore {
  let postID: String
  private(set) var post: Loci_Boards_V1_Post?
  private(set) var comments: [Loci_Boards_V1_Comment] = [] {
    didSet { rows = BoardsModel.flatten(BoardsModel.commentTree(comments)) }
  }
  /// The thread in reading order with each comment's depth, rebuilt only when the comments change.
  private(set) var rows: [(comment: Loci_Boards_V1_Comment, depth: Int)] = []
  private(set) var failed: String?
  var error: String?
  let feed: BoardsFeedStore

  init(postID: String, feed: BoardsFeedStore) {
    self.postID = postID
    self.feed = feed
  }

  func load() async {
    do {
      let response = try await feed.service.post(id: postID)
      post = response.post
      comments = response.comments
      failed = nil
    } catch {
      guard !(error is CancellationError), (error as? APIError) != .cancelled else { return }
      if post == nil { failed = error.userMessage } else { self.error = error.userMessage }
    }
  }

  func vote(pressed: Int32) async {
    guard feed.signedIn else {
      error = "Sign in to vote."
      return
    }
    guard let before = post else { return }
    let next = BoardsModel.applyVote(score: before.score, myVote: before.myVote, pressed: pressed)
    post?.score = next.score
    post?.myVote = next.myVote
    do {
      let result = try await feed.service.vote(postID: postID, value: next.myVote)
      post?.score = result.score
      post?.myVote = result.myVote
    } catch {
      post = before
      self.error = error.userMessage
    }
  }

  /// True when the comment was posted.
  func comment(_ body: String, parentID: String?) async -> Bool {
    let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return false }
    do {
      _ = try await feed.service.comment(postID: postID, parentID: parentID, body: text)
      await load()
      return true
    } catch {
      self.error = error.userMessage
      return false
    }
  }

  func deleteComment(_ comment: Loci_Boards_V1_Comment) async {
    do {
      try await feed.service.deleteComment(id: comment.id)
      await load()
    } catch { self.error = error.userMessage }
  }

  /// True when the post is gone. A failure is reported here, on the post's own screen.
  func deletePost() async -> Bool {
    guard let post else { return false }
    do {
      try await feed.removePost(post)
      return true
    } catch {
      self.error = error.userMessage
      return false
    }
  }
}
