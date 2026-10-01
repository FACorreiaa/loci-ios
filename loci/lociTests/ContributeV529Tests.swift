import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Contribute against proto v5.29.0: badges carry the server's own copy, and
/// Your reports pages through ListMyClaims.
struct ContributeV529Tests {
  // MARK: - Badges

  @Test func badgeDetailsCarryTheServersWording() {
    var proto = Loci_Place_ContributorProfile()
    proto.reputation = 40
    proto.badges = ["local-scout", "night-owl"]
    var scout = Loci_Place_Badge()
    scout.slug = "local-scout"
    scout.displayName = "Local Scout"
    scout.description_p = "Ten reports confirmed by another scout."
    var owl = Loci_Place_Badge()
    owl.slug = "night-owl"
    owl.displayName = "  "
    var blank = Loci_Place_Badge()
    blank.slug = ""
    proto.badgeDetails = [scout, owl, blank]

    let profile = ContributorProfile(proto)
    #expect(profile.shownBadges.map(\.slug) == ["local-scout", "night-owl"], "a badge without a slug is dropped")
    #expect(profile.shownBadges[0].title == "Local Scout", "the server's name, not this build's")
    #expect(profile.shownBadges[0].detail == "Ten reports confirmed by another scout.")
    #expect(profile.shownBadges[1].title == "Night owl", "a blank name falls back to the slug in words")
    #expect(profile.shownBadges[1].detail == nil)
  }

  @Test func slugsAloneFallBackToTheLocalWording() {
    var proto = Loci_Place_ContributorProfile()
    proto.badges = ["local-scout", "first_light"]
    let badges = ContributorProfile(proto).shownBadges
    #expect(badges.map(\.title) == ["Local scout", "First light"])
    #expect(badges[0].detail == "Ten reports verified by another scout")
    #expect(badges[1].detail == nil)
    #expect(ContributorProfile.empty.shownBadges.isEmpty)
  }

  // MARK: - Your reports

  @Test func claimRowsReadTheVocabularyAndTheOutcome() {
    let poiID = "5f0c0000-0000-4000-8000-000000000001"
    let claim = MyClaim(id: "c", poiID: poiID, placeName: "Fábrica", field: .dietary, value: "vegan", status: .accepted)
    #expect(claim.fieldLabel == PlaceFactVocabulary.label(.dietary))
    #expect(claim.valueText == "Vegan")
    #expect(claim.statusText == "Verified")
    #expect(claim.opensPlace)

    let hours = MyClaim(id: "h", poiID: "x", placeName: "", field: .openingHours, value: "mon-fri 09:00-17:00", status: .contradicted)
    #expect(hours.valueText == "mon-fri 09:00-17:00", "a structured value stays as sent")
    #expect(hours.statusText == "Noted")
    #expect(hours.placeName == MyClaim.removedPlaceName)
    #expect(!hours.opensPlace, "a removed place has nothing to open")
    #expect(MyClaim.statusText(.pending) == "Recorded")
  }

  @Test func claimsPagingFollowsTheServersTotal() {
    #expect(ContributePayload.claimsHaveMore(page: 1, received: 20, total: 23))
    #expect(!ContributePayload.claimsHaveMore(page: 2, received: 3, total: 23))
    #expect(!ContributePayload.claimsHaveMore(page: 1, received: 20, total: 20))
    #expect(ContributePayload.claimsHaveMore(page: 1, received: 20, total: 0), "no total: a full page may have a next one")
    #expect(!ContributePayload.claimsHaveMore(page: 1, received: 7, total: 0))
    #expect(!ContributePayload.claimsHaveMore(page: 1, received: 0, total: 50), "an empty page ends the list")
    let request = ContributePayload.myClaims(page: 2)
    #expect(request.limit == 20)
    #expect(request.page == 2)
  }

  @Test func claimsPageMapsTheResponse() {
    var response = Loci_Place_ListMyClaimsResponse()
    response.total = 21
    response.claims = (1...20).map { index in
      var claim = Loci_Place_MyPlaceClaim()
      claim.claimID = "c-\(index)"
      claim.field = .vibe
      claim.value = "cosy"
      return claim
    }
    let first = MyClaimsPage(response, page: 1)
    #expect(first.claims.count == 20)
    #expect(first.total == 21)
    #expect(first.hasMore)
  }

  @MainActor @Test func storePagesWithoutDuplicates() async {
    let store = MyReportsStore(service: PreviewContributeService())
    await store.load()
    #expect(store.phase == .loaded)
    #expect(store.claims.count == 20)
    #expect(store.total == 23)
    #expect(store.hasMore)
    await store.loadMore()
    #expect(store.claims.count == 23)
    #expect(Set(store.claims.map(\.id)).count == 23)
    #expect(!store.hasMore)
    await store.loadMore()
    #expect(store.claims.count == 23, "nothing more to ask for")
  }

  @MainActor @Test func storeWithNoReportsIsLoadedAndEmpty() async {
    let store = MyReportsStore(service: PreviewContributeService(claimCount: 0))
    await store.load()
    #expect(store.phase == .loaded)
    #expect(store.claims.isEmpty)
    #expect(!store.hasMore)
  }
}
