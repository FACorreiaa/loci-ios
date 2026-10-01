import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Pass 3, Phase 1: share by link. A target names what is shared and maps to
/// the server's content type; the sheet item starts with the text share and
/// swaps in the link once the server minted one, so ShareLink never waits.
struct ShareTargetTests {
  @Test func placeKindsMapToTheServerContentTypes() {
    #expect(ShareTarget.place(id: "p", name: "n", destination: .hotels, address: "").contentType == .hotel)
    #expect(ShareTarget.place(id: "p", name: "n", destination: .restaurants, address: "").contentType == .restaurant)
    #expect(ShareTarget.place(id: "p", name: "n", destination: .activities, address: "").contentType == .activity)
    #expect(ShareTarget.place(id: "p", name: "n", destination: .itinerary, address: "").contentType == .poi)
    #expect(ShareTarget.itinerary(id: "i", title: "t").contentType == .itinerary)
    #expect(ShareTarget.list(id: "l", name: "n").contentType == .list)
  }

  @Test func fallbackTextIsTodaysTextShare() {
    let place = ShareTarget.place(id: "p", name: "Tasca do Chico", destination: .restaurants, address: "Rua do Diário 39")
    #expect(place.fallbackText == "Tasca do Chico\nRua do Diário 39\nGenerated from Loci\nhttps://lociai.fyi")
    #expect(ShareTarget.list(id: "l", name: "Lisbon cafés").fallbackText == "Lisbon cafés\nGenerated from Loci\nhttps://lociai.fyi")
    #expect(ShareTarget.itinerary(id: "i", title: "Porto weekend").fallbackText == "Porto weekend\nGenerated from Loci\nhttps://lociai.fyi")
  }

  @Test func onlyStoredPlacesCanBeLinked() {
    let uuid = "7d1d9a2e-6b4f-4c1b-9d3e-1a2b3c4d5e6f"
    #expect(ShareTarget.place(id: uuid, name: "n", destination: .itinerary, address: "").canLink)
    #expect(!ShareTarget.place(id: "name:Tasca", name: "n", destination: .itinerary, address: "").canLink)
    #expect(!ShareTarget.list(id: "", name: "n").canLink)
    #expect(ShareTarget.itinerary(id: "i", title: "t").canLink)
  }

  @Test func shareLinkURLs() {
    #expect(ShareLinks.share(code: "abc")?.absoluteString == "https://lociai.fyi/share/abc")
    #expect(ShareLinks.share(code: "") == nil)
  }

  @MainActor @Test func sheetItemStartsWithTextAndSwapsInTheLink() async {
    let target = ShareTarget.list(id: "l1", name: "Lisbon cafés")
    let item = ShareSheetItem(target: target) { _ in URL(string: "https://lociai.fyi/share/xyz")! }
    #expect(item.text == target.fallbackText)
    #expect(item.url == nil)
    await item.prepare()
    #expect(item.url?.absoluteString == "https://lociai.fyi/share/xyz")
    #expect(item.text == "Lisbon cafés\nhttps://lociai.fyi/share/xyz", "the link replaces the signature and home page")
  }

  @MainActor @Test func sheetItemKeepsTheTextWhenTheLinkFails() async {
    let target = ShareTarget.itinerary(id: "i1", title: "Porto weekend")
    let item = ShareSheetItem(target: target) { _ in throw APIError.network("down") }
    await item.prepare()
    #expect(item.url == nil)
    #expect(item.text == target.fallbackText)
    #expect(item.attempted, "a failed mint is not retried on every redraw")
  }

  @MainActor @Test func sheetItemDoesNotMintForUnlinkablePlaces() async {
    let target = ShareTarget.place(id: "name:x", name: "x", destination: .itinerary, address: "")
    let item = ShareSheetItem(target: target) { _ in
      Issue.record("no mint for a name-keyed place")
      return URL(string: "https://lociai.fyi")!
    }
    await item.prepare()
    #expect(item.url == nil)
  }
}
