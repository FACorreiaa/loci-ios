import Foundation
import LociConnectProto
import Testing

@testable import loci

@MainActor
struct TripCommentsTests {
  private func comment(mine: Bool = false, author: String = "Rui", stopID: String = "") -> Loci_Trip_TripComment {
    var c = Loci_Trip_TripComment()
    c.id = "c1"
    c.mine = mine
    c.stopID = stopID
    c.author.username = author.lowercased()
    c.author.displayName = author
    return c
  }

  private func stop(_ id: String, _ name: String) -> Loci_Trip_TripStop {
    var s = Loci_Trip_TripStop()
    s.id = id
    s.name = name
    return s
  }

  @Test func bylineNamesWhoAndWhatItIsAbout() {
    let stops = [stop("s1", "Miradouro da Graça")]
    #expect(TripCommentsSection.byline(comment(), stops: stops) == "Rui")
    #expect(TripCommentsSection.byline(comment(mine: true, stopID: "s1"), stops: stops) == "You · on Miradouro da Graça")
    // A stop that has left the trip: the comment reads as the trip's.
    #expect(TripCommentsSection.byline(comment(stopID: "gone"), stops: stops) == "Rui")
  }

  @Test func titleSaysWhenOlderCommentsRemain() {
    #expect(TripCommentsSection.title(count: 3, hasMore: false) == "Comments · 3")
    #expect(TripCommentsSection.title(count: 100, hasMore: true) == "Comments · 100+")
  }

  @Test func olderCommentsGoAboveWithoutRepeats() {
    func withID(_ id: String) -> Loci_Trip_TripComment {
      var c = comment()
      c.id = id
      return c
    }
    let shown = [withID("c3"), withID("c4")]
    let merged = TripEditorView.prepending([withID("c1"), withID("c2"), withID("c3")], to: shown)
    #expect(merged.map(\.id) == ["c1", "c2", "c3", "c4"])
  }

  @Test func reportReasonsAreTheServers() {
    #expect(TripCommentsAPI.reportReasons.map(\.value) == ["spam", "inappropriate", "offensive", "other"])
  }
}
