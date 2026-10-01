import Foundation
import Testing

@testable import loci

struct AppLinkTests {
  @Test(arguments: [
    ("loci://lists/l1", AppLink.list(id: "l1")),
    ("loci://packs/lisbon-3-days", .pack(slug: "lisbon-3-days")),
    ("loci://trips/t1", .trip(id: "t1")),
    ("loci://recents", .recents),
    ("loci://contribute", .contribute),
    ("https://lociai.fyi/lists/l1", .list(id: "l1")),
    ("https://www.lociai.fyi/packs/lisbon-3-days", .pack(slug: "lisbon-3-days")),
    ("https://lociai.fyi/trips/t1?tab=days", .trip(id: "t1")),
    ("https://lociai.fyi/recents", .recents),
    ("https://LOCIAI.FYI/contribute/", .contribute),
    ("https://lociai.fyi/t/abc123", .sharedTrip(code: "abc123")),
    ("https://lociai.fyi/invite/inv1", .invite(code: "inv1")),
    ("https://lociai.fyi/u/ana", .user(username: "ana")),
    ("https://lociai.fyi/friends", .friends),
    ("https://lociai.fyi/friends?tab=add", .friends),
    ("https://lociai.fyi/friends/trips/t2", .friendTrip(id: "t2")),
    ("loci://u/ana", .user(username: "ana")),
    ("https://lociai.fyi/share/abc", .shared(code: "abc")),
    ("https://api.lociai.fyi/share/abc", .shared(code: "abc")),
    ("loci://share/abc", .shared(code: "abc")),
  ])
  func parsesEveryRoute(_ string: String, _ expected: AppLink) throws {
    #expect(AppLink(url: try #require(URL(string: string))) == expected)
  }

  @Test(arguments: [
    "loci://lists",
    "loci://lists/",
    "loci://trips/t1/edit",
    "loci://recents/extra",
    "loci://oauth2redirect/google?code=x",
    "loci://itinerary?sessionId=abc",
    "https://example.com/lists/l1",
    "https://lociai.fyi/lists",
    "https://lociai.fyi/packs/a/b",
    "https://lociai.fyi/pricing",
    "http://lociai.fyi/lists/l1",
    "https://lociai.fyi/t",
    "https://lociai.fyi/u/ana/trips",
    "https://lociai.fyi/friends/feed/t2",
    "mailto:hi@lociai.fyi",
  ])
  func rejectsIncompleteAndForeignLinks(_ string: String) throws {
    #expect(AppLink(url: try #require(URL(string: string))) == nil)
  }

  /// A result link must keep opening the session, not fall through to AppLink.
  @Test func sessionLinksAreNotAppLinks() throws {
    let url = try #require(URL(string: "https://lociai.fyi/itinerary?sessionId=abc"))
    #expect(SessionLink(url: url) != nil)
    #expect(AppLink(url: url) == nil)
  }

  @MainActor @Test(arguments: [
    (AppLink.list(id: "l1"), AppRouter.Tab.saved),
    (.pack(slug: "p"), .discover),
    (.trip(id: "t1"), .calendar),
    (.recents, .profile),
    (.contribute, .profile),
    (.sharedTrip(code: "c"), .profile),
    (.invite(code: "c"), .profile),
    (.user(username: "ana"), .profile),
    (.friends, .profile),
    (.friendTrip(id: "t2"), .profile),
    (.resetPassword(token: "t"), .profile),
    (.confirmEmail(token: "t"), .profile),
    (.shared(code: "abc"), .discover),
  ])
  func routesToTheOwningTab(_ link: AppLink, _ tab: AppRouter.Tab) {
    let router = AppRouter()
    router.open(link)
    #expect(router.selectedTab == tab)
    #expect(router.takeLink(for: tab == .saved ? .profile : .saved) == nil)
    #expect(router.takeLink(for: tab) == link)
    #expect(router.pendingLink == nil)
  }

  @MainActor @Test func openURLPrefersSessionLinks() throws {
    let router = AppRouter()
    #expect(router.open(try #require(URL(string: "loci://hotels?sessionId=s1"))))
    #expect(router.selectedTab == .assistant)
    #expect(router.pendingSession?.sessionId == "s1")
    #expect(router.pendingLink == nil)

    #expect(router.open(try #require(URL(string: "https://lociai.fyi/trips/t9"))))
    #expect(router.selectedTab == .calendar)
    #expect(router.pendingLink == .trip(id: "t9"))

    #expect(!router.open(try #require(URL(string: "https://lociai.fyi/pricing"))))
  }
}
