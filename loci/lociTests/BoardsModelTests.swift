import Foundation
import LociConnectProto
import Testing

@testable import loci

/// The boards rules shared with web (lib/api/boards.ts): votes, board
/// addresses, links, comment threading and what Saved can attach.
struct BoardsModelTests {
  @Test func votingFlipsAndClears() {
    #expect(BoardsModel.applyVote(score: 0, myVote: 0, pressed: 1) == (1, 1))
    #expect(BoardsModel.applyVote(score: 1, myVote: 1, pressed: -1) == (-1, -1))
    #expect(BoardsModel.applyVote(score: -1, myVote: -1, pressed: -1) == (0, 0))
  }

  @Test func slugifyMatchesTheServerRule() {
    #expect(BoardsModel.slugify("Trip reports!") == "trip-reports")
    #expect(BoardsModel.slugify("  São Paulo  eats ") == "sao-paulo-eats")
    #expect(BoardsModel.slugify(String(repeating: "x", count: 40)).count == 32)
    #expect(BoardsModel.isValidSlug("lisbon"))
    #expect(!BoardsModel.isValidSlug("ab"))
    #expect(!BoardsModel.isValidSlug("Lisbon"))
  }

  @Test func onlyHttpLinksWithAHost() {
    #expect(BoardsModel.isLink("https://www.example.com/x"))
    #expect(!BoardsModel.isLink("javascript:alert(1)"))
    #expect(!BoardsModel.isLink("example.com"))
  }

  @Test func commentsNestAndOrphansSurface() {
    func comment(_ id: String, _ parent: String = "") -> Loci_Boards_V1_Comment {
      var c = Loci_Boards_V1_Comment()
      c.id = id
      c.parentID = parent
      return c
    }
    let rows = BoardsModel.flatten(BoardsModel.commentTree([comment("a"), comment("b"), comment("a1", "a"), comment("x", "gone")]))
    #expect(rows.map(\.comment.id) == ["a", "a1", "b", "x"])
    #expect(rows.map(\.depth) == [0, 1, 0, 0])
  }

  @Test func onlyRealPOIsAttach() {
    var poi = Loci_Favorites_V1_FavoriteItem()
    poi.itemID = UUID().uuidString
    poi.contentType = .poi
    #expect(BoardsModel.attachable(poi))

    var hotel = poi
    hotel.contentType = .hotel
    #expect(!BoardsModel.attachable(hotel))

    var named = poi
    named.itemID = "Café Santiago"
    #expect(!BoardsModel.attachable(named))
  }
}
