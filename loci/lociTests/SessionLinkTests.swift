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
    "https://lociai.fyi/itinerary?sessionId=abc",
  ])
  func ignoresOAuthRedirectAndIncompleteLinks(_ string: String) throws {
    #expect(SessionLink(url: try #require(URL(string: string))) == nil)
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
