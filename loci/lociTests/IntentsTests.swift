import Foundation
import Testing

@testable import loci

struct IntentsTests {
  @Test func planDayLinkCarriesThePrompt() throws {
    let url = IntentRoute.url(for: .planDay(city: "São Paulo"))
    #expect(url.scheme == "loci")
    #expect(AppLink(url: url) == .plan(prompt: "Plan a day in São Paulo"))
  }

  @Test func planDayWithoutACityStillOpensTheComposer() {
    #expect(AppLink(url: IntentRoute.url(for: .planDay(city: "  "))) == .plan(prompt: "Plan a day"))
  }

  @Test func nearbyFitsOpensNearMe() {
    #expect(AppLink(url: IntentRoute.url(for: .nearbyFits)) == .nearby)
  }

  @MainActor @Test func intentLinksOpenOnDiscover() {
    #expect(AppRouter.tab(for: .plan(prompt: "x")) == .discover)
    #expect(AppRouter.tab(for: .nearby) == .discover)
  }

  /// A web page with the same path stays in Safari: these are the app's own links.
  @Test func webPlanLinkIsNotClaimed() throws {
    #expect(AppLink(url: try #require(URL(string: "https://lociai.fyi/plan?q=x"))) == nil)
    #expect(AppLink(url: try #require(URL(string: "https://lociai.fyi/nearby"))) == nil)
  }
}
