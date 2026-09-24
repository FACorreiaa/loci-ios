import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Ported from web's lib/recents/activity-link.test.ts: where each feed row goes.
struct ActivityDestinationTests {
  private func entry(
    kind: ActivityKind = .prompt,
    detail: String = "itinerary",
    label: String = "three days in Porto",
    city: String = "Porto",
    refId: String = "sess-1",
    id: String = "e1"
  ) -> ActivityEntry {
    ActivityEntry(id: id, kind: kind, detail: detail, label: label, cityName: city, refId: refId, occurredAt: Date())
  }

  private func search(_ destination: ActivityDestination?) -> (link: SessionLink, message: String)? {
    guard case let .search(link, message) = destination else { return nil }
    return (link, message)
  }

  @Test func routesEachDomainToThePageThatAnswersIt() {
    let cases: [(String, SearchDestination)] = [
      ("itinerary", .itinerary), ("general", .itinerary), ("accommodation", .hotels),
      ("dining", .restaurants), ("activities", .activities),
    ]
    for (detail, page) in cases {
      #expect(search(ActivityDestination(entry(detail: detail)))?.link.destination == page, "\(detail)")
    }
  }

  // The whole feature turns on this: a session that cannot be restored can
  // still be run again from its message.
  @Test func carriesTheOriginalMessageSessionAndCity() throws {
    let hit = try #require(search(ActivityDestination(entry(detail: "dining", label: "seafood in Cascais"))))
    #expect(hit.message == "seafood in Cascais")
    #expect(hit.link.sessionId == "sess-1")
    #expect(hit.link.cityName == "Porto")
    #expect(hit.link.domain == "dining")
  }

  @Test func anEmptyCityIsLeftOffTheLink() {
    #expect(search(ActivityDestination(entry(city: "")))?.link.cityName == nil)
  }

  @Test func nearbyWithASessionOpensThatSessionsResults() throws {
    let hit = try #require(search(ActivityDestination(entry(detail: "nearby"))))
    #expect(hit.link.destination == .itinerary)
    #expect(hit.link.domain == "nearby")
  }

  @Test func nearbyWithoutASessionOpensNearMe() {
    #expect(ActivityDestination(entry(detail: "nearby", refId: "")) == .nearby)
  }

  @Test func aKeptTripOpensBySavedIdAndItsSession() {
    #expect(
      ActivityDestination(entry(kind: .savedItinerary, refId: "sess-7", id: "saved-3"))
        == .savedItinerary(id: "saved-3", sessionId: "sess-7")
    )
    let noSession = ActivityDestination(entry(kind: .savedItinerary, refId: "", id: "saved-3"))
    #expect(noSession == .savedItinerary(id: "saved-3", sessionId: ""))
  }

  @Test func aFavouriteOpensAsASavedPlaceOfItsKind() {
    func favourite(_ detail: String) -> Loci_Favorites_V1_FavoriteItem? {
      let destination = ActivityDestination(entry(kind: .favourite, detail: detail, label: "Casa", refId: "item-1", id: "fav-1"))
      guard case .favourite(let item) = destination else { return nil }
      return item
    }
    #expect(favourite("hotel")?.contentType == .hotel)
    #expect(favourite("restaurant")?.contentType == .restaurant)
    #expect(favourite("poi")?.contentType == .poi)
    let item = favourite("poi")
    #expect(item?.id == "fav-1")
    #expect(item?.itemID == "item-1")
    #expect(item?.itemName == "Casa")
    #expect(item?.cityName == "Porto")
  }

  @Test func aFavouritedItineraryOpensTheSavedItinerary() {
    #expect(ActivityDestination(entry(kind: .favourite, detail: "itinerary", refId: "it-9")) == .savedItinerary(id: "it-9", sessionId: ""))
  }

  @Test func anUnknownKindOpensNothing() {
    #expect(ActivityDestination(entry(kind: .other)) == nil)
  }

  @Test func savedItineraryIsFoundByIdThenBySession() {
    var first = Loci_Itinerary_UserSavedItinerary()
    first.id = "saved-1"
    first.sessionID = "sess-1"
    var second = Loci_Itinerary_UserSavedItinerary()
    second.id = "saved-2"
    second.sessionID = "sess-2"
    let all = [first, second]
    #expect(SavedItineraryMatch.find(in: all, id: "saved-2", sessionId: "sess-1")?.id == "saved-2")
    #expect(SavedItineraryMatch.find(in: all, id: "gone", sessionId: "sess-1")?.id == "saved-1")
    #expect(SavedItineraryMatch.find(in: all, id: "gone", sessionId: "") == nil)
    #expect(SavedItineraryMatch.find(in: [], id: "saved-1", sessionId: "sess-1") == nil)
  }
}
