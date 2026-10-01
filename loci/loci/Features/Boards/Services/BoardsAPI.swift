import Foundation
import LociConnectProto
import SwiftProtobuf

/// BoardsService (loci.boards.v1), web: lib/api/boards.ts.
///
/// Community boards: topic boards, posts with an optional link and an optional
/// Loci item, threaded comments and post votes. Reads work signed out; the
/// server is the only gate on writes and on the admin actions.
nonisolated enum BoardsAPI {
  private static let client = Loci_Boards_V1_BoardsServiceClient(client: ConnectTransport.shared.protocolClient)

  static func boards() async throws -> [Loci_Boards_V1_Board] {
    var request = Loci_Boards_V1_ListBoardsRequest()
    request.pageSize = 100
    return try await rpc("Could not load boards.", request) { await client.listBoards(request: $0, headers: [:]) }.boards
  }

  static func board(slug: String) async throws -> Loci_Boards_V1_Board {
    var request = Loci_Boards_V1_GetBoardRequest()
    request.slug = slug
    return try await rpc("Could not load this board.", request) { await client.getBoard(request: $0, headers: [:]) }.board
  }

  static func posts(board: String, sort: Loci_Boards_V1_PostSort, window: Loci_Boards_V1_TopWindow, cursor: String) async throws
    -> Loci_Boards_V1_ListPostsResponse
  {
    var request = Loci_Boards_V1_ListPostsRequest()
    request.boardSlug = board
    request.sort = sort
    request.window = window
    request.cursor = cursor
    request.pageSize = 30
    return try await rpc("Could not load posts.", request) { await client.listPosts(request: $0, headers: [:]) }
  }

  static func post(id: String) async throws -> Loci_Boards_V1_GetPostResponse {
    var request = Loci_Boards_V1_GetPostRequest()
    request.id = id
    return try await rpc("Could not load this post.", request) { await client.getPost(request: $0, headers: [:]) }
  }

  static func viewer() async throws -> Loci_Boards_V1_GetBoardsViewerResponse {
    let request = Loci_Boards_V1_GetBoardsViewerRequest()
    return try await rpc("Could not load boards.", request) { await client.getBoardsViewer(request: $0, headers: [:]) }
  }

  static func createBoard(slug: String, name: String, description: String) async throws -> Loci_Boards_V1_Board {
    var request = Loci_Boards_V1_CreateBoardRequest()
    request.slug = slug
    request.name = name
    request.description_p = description
    return try await rpc("Could not open the board.", request) { await client.createBoard(request: $0, headers: [:]) }.board
  }

  static func createPost(_ request: Loci_Boards_V1_CreatePostRequest) async throws -> Loci_Boards_V1_Post {
    try await rpc("Could not post.", request) { await client.createPost(request: $0, headers: [:]) }.post
  }

  static func deletePost(id: String) async throws {
    var request = Loci_Boards_V1_DeletePostRequest()
    request.id = id
    _ = try await rpc("Could not delete the post.", request) { await client.deletePost(request: $0, headers: [:]) }
  }

  static func comment(postID: String, parentID: String?, body: String) async throws -> Loci_Boards_V1_Comment {
    var request = Loci_Boards_V1_CreateCommentRequest()
    request.postID = postID
    request.parentID = parentID ?? ""
    request.body = body
    return try await rpc("Could not comment.", request) { await client.createComment(request: $0, headers: [:]) }.comment
  }

  static func deleteComment(id: String) async throws {
    var request = Loci_Boards_V1_DeleteCommentRequest()
    request.id = id
    _ = try await rpc("Could not delete the comment.", request) { await client.deleteComment(request: $0, headers: [:]) }
  }

  static func vote(postID: String, value: Int32) async throws -> Loci_Boards_V1_VotePostResponse {
    var request = Loci_Boards_V1_VotePostRequest()
    request.postID = postID
    request.value = value
    return try await rpc("Could not vote.", request) { await client.votePost(request: $0, headers: [:]) }
  }

  static func deleteBoard(slug: String) async throws {
    var request = Loci_Boards_V1_DeleteBoardRequest()
    request.slug = slug
    _ = try await rpc("Could not delete the board.", request) { await client.deleteBoard(request: $0, headers: [:]) }
  }

  static func sanction(userID: String, kind: Loci_Boards_V1_SanctionKind, reason: String, days: Int?) async throws {
    var request = Loci_Boards_V1_SanctionUserRequest()
    request.userID = userID
    request.kind = kind
    request.reason = reason
    if let days { request.expiresAt = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(Double(days) * 86_400)) }
    _ = try await rpc("Could not apply that.", request) { await client.sanctionUser(request: $0, headers: [:]) }
  }

  static func liftSanction(id: String) async throws {
    var request = Loci_Boards_V1_LiftSanctionRequest()
    request.id = id
    _ = try await rpc("Could not lift it.", request) { await client.liftSanction(request: $0, headers: [:]) }
  }

  static func sanctions() async throws -> [Loci_Boards_V1_Sanction] {
    let request = Loci_Boards_V1_ListSanctionsRequest()
    return try await rpc("Could not load sanctions.", request) { await client.listSanctions(request: $0, headers: [:]) }.sanctions
  }
}

/// What the boards screens need from the server, behind a protocol so the
/// design previews and tests run without a session.
nonisolated protocol BoardsService: Sendable {
  func boards() async throws -> [Loci_Boards_V1_Board]
  func board(slug: String) async throws -> Loci_Boards_V1_Board
  func posts(board: String, sort: Loci_Boards_V1_PostSort, window: Loci_Boards_V1_TopWindow, cursor: String) async throws
    -> Loci_Boards_V1_ListPostsResponse
  func post(id: String) async throws -> Loci_Boards_V1_GetPostResponse
  func viewer() async throws -> Loci_Boards_V1_GetBoardsViewerResponse
  func createBoard(slug: String, name: String, description: String) async throws -> Loci_Boards_V1_Board
  func createPost(_ request: Loci_Boards_V1_CreatePostRequest) async throws -> Loci_Boards_V1_Post
  func deletePost(id: String) async throws
  func comment(postID: String, parentID: String?, body: String) async throws -> Loci_Boards_V1_Comment
  func deleteComment(id: String) async throws
  func vote(postID: String, value: Int32) async throws -> Loci_Boards_V1_VotePostResponse
  func deleteBoard(slug: String) async throws
  func sanction(userID: String, kind: Loci_Boards_V1_SanctionKind, reason: String, days: Int?) async throws
  func liftSanction(id: String) async throws
  func sanctions() async throws -> [Loci_Boards_V1_Sanction]
}

nonisolated struct ConnectBoardsService: BoardsService {
  func boards() async throws -> [Loci_Boards_V1_Board] { try await BoardsAPI.boards() }
  func board(slug: String) async throws -> Loci_Boards_V1_Board { try await BoardsAPI.board(slug: slug) }
  func posts(board: String, sort: Loci_Boards_V1_PostSort, window: Loci_Boards_V1_TopWindow, cursor: String) async throws
    -> Loci_Boards_V1_ListPostsResponse
  { try await BoardsAPI.posts(board: board, sort: sort, window: window, cursor: cursor) }
  func post(id: String) async throws -> Loci_Boards_V1_GetPostResponse { try await BoardsAPI.post(id: id) }
  func viewer() async throws -> Loci_Boards_V1_GetBoardsViewerResponse { try await BoardsAPI.viewer() }
  func createBoard(slug: String, name: String, description: String) async throws -> Loci_Boards_V1_Board {
    try await BoardsAPI.createBoard(slug: slug, name: name, description: description)
  }
  func createPost(_ request: Loci_Boards_V1_CreatePostRequest) async throws -> Loci_Boards_V1_Post { try await BoardsAPI.createPost(request) }
  func deletePost(id: String) async throws { try await BoardsAPI.deletePost(id: id) }
  func comment(postID: String, parentID: String?, body: String) async throws -> Loci_Boards_V1_Comment {
    try await BoardsAPI.comment(postID: postID, parentID: parentID, body: body)
  }
  func deleteComment(id: String) async throws { try await BoardsAPI.deleteComment(id: id) }
  func vote(postID: String, value: Int32) async throws -> Loci_Boards_V1_VotePostResponse { try await BoardsAPI.vote(postID: postID, value: value) }
  func deleteBoard(slug: String) async throws { try await BoardsAPI.deleteBoard(slug: slug) }
  func sanction(userID: String, kind: Loci_Boards_V1_SanctionKind, reason: String, days: Int?) async throws {
    try await BoardsAPI.sanction(userID: userID, kind: kind, reason: reason, days: days)
  }
  func liftSanction(id: String) async throws { try await BoardsAPI.liftSanction(id: id) }
  func sanctions() async throws -> [Loci_Boards_V1_Sanction] { try await BoardsAPI.sanctions() }
}
