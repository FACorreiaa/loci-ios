import Foundation
import Testing

@testable import loci

struct SessionLinkTests {
  @Test func parsesItineraryDeepLink() throws {
    let url = try #require(URL(string: "loci://itinerary?sessionId=abc&cityName=Lisbon&domain=itinerary"))
    let link = try #require(SessionLink(url: url))
    #expect(link == SessionLink(destination: .itinerary, sessionId: "abc", cityName: "Lisbon", domain: "itinerary"))
  }

  @Test func parsesEveryWebResultRoute() {
    for destination in SearchDestination.allCases {
      let url = URL(string: "loci://\(destination.rawValue)?sessionId=s1")
      #expect(url.flatMap(SessionLink.init(url:))?.destination == destination)
    }
  }

  @Test(arguments: [
    "loci://oauth2redirect/google?code=x",
    "loci://itinerary?cityName=Lisbon",
    "loci://itinerary?sessionId=",
    "https://example.com/itinerary?sessionId=abc",
    "https://lociai.fyi/pricing",
    "https://lociai.fyi/itinerary",
  ])
  func ignoresOAuthRedirectAndIncompleteLinks(_ string: String) throws {
    #expect(SessionLink(url: try #require(URL(string: string))) == nil)
  }

  @Test func parsesUniversalLinks() throws {
    let url = try #require(URL(string: "https://lociai.fyi/hotels?sessionId=abc&cityName=Rome&domain=hotels"))
    #expect(SessionLink(url: url) == SessionLink(destination: .hotels, sessionId: "abc", cityName: "Rome", domain: "hotels"))
    let www = try #require(URL(string: "https://www.lociai.fyi/itinerary?sessionId=abc"))
    #expect(SessionLink(url: www)?.destination == .itinerary)
    let nearme = try #require(URL(string: "https://lociai.fyi/nearme?sessionId=n1&cityName=nearme"))
    #expect(SessionLink(url: nearme)?.destination == .itinerary)
    #expect(SessionLink(url: nearme)?.sessionId == "n1")
  }

  @Test func roundTripsThroughURLAndUserInfo() throws {
    let link = SessionLink(destination: .hotels, sessionId: "s 1", cityName: "São Paulo", domain: "accommodation")
    #expect(SessionLink(url: try #require(link.url)) == link)
    #expect(SessionLink(userInfo: link.userInfo) == link)
  }

  @Test func mapsServerDomainsLikeWeb() {
    #expect(SearchDestination(domain: "general") == .itinerary)
    #expect(SearchDestination(domain: "itinerary") == .itinerary)
    #expect(SearchDestination(domain: "accommodation") == .hotels)
    #expect(SearchDestination(domain: "dining") == .restaurants)
    #expect(SearchDestination(domain: "activities") == .activities)
    #expect(SearchDestination(domain: "transport") == .itinerary)
  }
}
