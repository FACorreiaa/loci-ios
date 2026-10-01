import Foundation
import LociConnectProto
import SwiftProtobuf

/// Offline sample data for `-designPreview boards` / `boardsPost` and previews.
/// The viewer is an admin, so every control shows.
nonisolated struct PreviewBoardsService: BoardsService {
  func boards() async throws -> [Loci_Boards_V1_Board] {
    [.preview("lisbon", "Lisbon", posts: 2), .preview("trip-reports", "Trip reports", posts: 1)]
  }
  func board(slug: String) async throws -> Loci_Boards_V1_Board { .preview(slug, slug == "lisbon" ? "Lisbon" : "Trip reports", posts: 2) }
  func posts(board: String, sort: Loci_Boards_V1_PostSort, window: Loci_Boards_V1_TopWindow, cursor: String) async throws
    -> Loci_Boards_V1_ListPostsResponse
  {
    var response = Loci_Boards_V1_ListPostsResponse()
    response.posts = Loci_Boards_V1_Post.previewFeed.filter { board.isEmpty || $0.board.slug == board }
    if sort == .top { response.posts.sort { $0.score > $1.score } }
    return response
  }
  func post(id: String) async throws -> Loci_Boards_V1_GetPostResponse {
    var response = Loci_Boards_V1_GetPostResponse()
    response.post = Loci_Boards_V1_Post.previewFeed.first { $0.id == id } ?? Loci_Boards_V1_Post.previewFeed[0]
    response.comments = Loci_Boards_V1_Comment.previewThread
    return response
  }
  func viewer() async throws -> Loci_Boards_V1_GetBoardsViewerResponse {
    var viewer = Loci_Boards_V1_GetBoardsViewerResponse()
    viewer.signedIn = true
    viewer.isAdmin = true
    return viewer
  }
  func createBoard(slug: String, name: String, description: String) async throws -> Loci_Boards_V1_Board { .preview(slug, name, posts: 0) }
  func createPost(_ request: Loci_Boards_V1_CreatePostRequest) async throws -> Loci_Boards_V1_Post { Loci_Boards_V1_Post.previewFeed[0] }
  func deletePost(id: String) async throws {}
  func comment(postID: String, parentID: String?, body: String) async throws -> Loci_Boards_V1_Comment { Loci_Boards_V1_Comment.previewThread[0] }
  func deleteComment(id: String) async throws {}
  func vote(postID: String, value: Int32) async throws -> Loci_Boards_V1_VotePostResponse {
    var response = Loci_Boards_V1_VotePostResponse()
    let post = Loci_Boards_V1_Post.previewFeed.first { $0.id == postID }
    response.score = (post?.score ?? 0) - (post?.myVote ?? 0) + value
    response.myVote = value
    return response
  }
  func deleteBoard(slug: String) async throws {}
  func sanction(userID: String, kind: Loci_Boards_V1_SanctionKind, reason: String, days: Int?) async throws {}
  func liftSanction(id: String) async throws {}
  func sanctions() async throws -> [Loci_Boards_V1_Sanction] {
    var s = Loci_Boards_V1_Sanction()
    s.id = "s-1"
    s.user = .preview("u-spam", "Deal Hunter")
    s.kind = .mute
    s.reason = "Link spam"
    s.createdAt = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(-86_400))
    s.expiresAt = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(6 * 86_400))
    return [s]
  }
}

nonisolated extension Loci_Social_PublicUser {
  static func preview(_ id: String, _ name: String) -> Loci_Social_PublicUser {
    var u = Loci_Social_PublicUser()
    u.id = id
    u.displayName = name
    u.username = name.lowercased().replacingOccurrences(of: " ", with: "")
    return u
  }
}

nonisolated extension Loci_Boards_V1_Board {
  static func preview(_ slug: String, _ name: String, posts: Int32) -> Loci_Boards_V1_Board {
    var b = Loci_Boards_V1_Board()
    b.id = "b-\(slug)"
    b.slug = slug
    b.name = name
    b.description_p = "Where to eat, sleep and walk in \(name)."
    b.postCount = posts
    b.createdBy = .preview("u-ana", "Ana Sousa")
    return b
  }
}

nonisolated extension Loci_Boards_V1_Post {
  static var previewFeed: [Loci_Boards_V1_Post] {
    func post(
      _ id: String,
      _ board: (String, String),
      _ title: String,
      by author: Loci_Social_PublicUser,
      hoursAgo: Double,
      score: Int32,
      comments: Int32
    ) -> Loci_Boards_V1_Post {
      var p = Loci_Boards_V1_Post()
      p.id = id
      p.board.slug = board.0
      p.board.name = board.1
      p.title = title
      p.author = author
      p.score = score
      p.commentCount = comments
      p.createdAt = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(-hoursAgo * 3600))
      return p
    }
    var trams = post(
      "p-trams",
      ("lisbon", "Lisbon"),
      "Tram 28 is a queue, not a ride. Take the 12E instead",
      by: .preview("u-rui", "Rui Costa"),
      hoursAgo: 3,
      score: 14,
      comments: 4
    )
    trams.body = "Same hills, a tenth of the crowd. **Board at Praça da Figueira** before 9 and you'll have the window seat."
    trams.myVote = 1
    var attachment = Loci_Boards_V1_Attachment()
    attachment.kind = .poi
    attachment.ref = "00000000-0000-0000-0000-000000000028"
    attachment.title = "Miradouro da Graça"
    attachment.subtitle = "viewpoint"
    attachment.city = "Lisbon"
    trams.attachment = attachment

    var porto = post(
      "p-porto",
      ("trip-reports", "Trip reports"),
      "Three days in Porto without a car",
      by: .preview("u-ana", "Ana Sousa"),
      hoursAgo: 20,
      score: 6,
      comments: 2
    )
    porto.url = "https://www.example.com/porto-on-foot"
    porto.domain = "example.com"

    let alfama = post(
      "p-alfama",
      ("lisbon", "Lisbon"),
      "Is Alfama still worth it on a Saturday?",
      by: .preview("u-mia", "Mia"),
      hoursAgo: 30,
      score: -1,
      comments: 0
    )
    return [trams, porto, alfama]
  }
}

nonisolated extension Loci_Boards_V1_Comment {
  static var previewThread: [Loci_Boards_V1_Comment] {
    func comment(_ id: String, parent: String = "", by author: Loci_Social_PublicUser?, _ body: String, hoursAgo: Double) -> Loci_Boards_V1_Comment {
      var c = Loci_Boards_V1_Comment()
      c.id = id
      c.postID = "p-trams"
      c.parentID = parent
      if let author { c.author = author } else { c.deleted = true }
      c.body = author == nil ? "" : body
      c.createdAt = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(-hoursAgo * 3600))
      return c
    }
    return [
      comment("c1", by: .preview("u-ana", "Ana Sousa"), "Can confirm. The 12E loops in 20 minutes.", hoursAgo: 2.5),
      comment("c2", parent: "c1", by: .preview("u-rui", "Rui Costa"), "And it passes Sé without the line.", hoursAgo: 2),
      comment("c3", parent: "c2", by: .preview("u-mia", "Mia"), "Saving this for October.", hoursAgo: 1), comment("c4", by: nil, "", hoursAgo: 1.5),
      comment("c5", parent: "c4", by: .preview("u-rui", "Rui Costa"), "Ignore the spam above.", hoursAgo: 1.2),
    ]
  }
}
