import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Pass 3, Phase 0: the account's plan and limits, read once per sign-in and
/// shown on the You hub. Nothing is gated by it while PlanGating is off.
struct EntitlementsTests {
  private func proto(plan: String, listsUsed: Int32 = 3, listsLimit: Int32 = 5, placesSaved: Int32 = 12, placesLimit: Int32 = 50) -> Loci_Entitlement_V1_Entitlements {
    var e = Loci_Entitlement_V1_Entitlements()
    e.plan = plan
    e.listsUsed = listsUsed
    e.listsLimit = listsLimit
    e.placesSaved = placesSaved
    e.placesLimit = placesLimit
    e.advancedFilters = plan == "pro"
    e.exportFull = plan == "pro"
    return e
  }

  @Test func protoMapsEveryField() {
    let e = Entitlements(proto(plan: "pro", listsUsed: 7, listsLimit: -1, placesSaved: 80, placesLimit: -1))
    #expect(e.plan == "pro")
    #expect(e.listsUsed == 7)
    #expect(e.listsLimit == -1)
    #expect(e.placesSaved == 80)
    #expect(e.placesLimit == -1)
    #expect(e.advancedFilters)
    #expect(e.exportFull)
    #expect(e.isPro)
  }

  @Test func freeDefaultsMatchTheServer() {
    #expect(Entitlements.free.plan == "free")
    #expect(Entitlements.free.listsLimit == 5)
    #expect(Entitlements.free.placesLimit == 50)
    #expect(!Entitlements.free.isPro)
    #expect(!Entitlements.free.advancedFilters)
  }

  @Test func unknownPlanIsFree() {
    #expect(!Entitlements(proto(plan: "")).isPro)
    #expect(!Entitlements(proto(plan: "enterprise")).isPro)
    #expect(Entitlements(proto(plan: "premium_annual")).isPro)
  }

  @Test func remainingIsNilWhenUnlimited() {
    let pro = Entitlements(proto(plan: "pro", listsLimit: -1, placesLimit: -1))
    #expect(pro.listsRemaining == nil)
    #expect(pro.placesRemaining == nil)
    let free = Entitlements(proto(plan: "free", listsUsed: 3, listsLimit: 5, placesSaved: 60, placesLimit: 50))
    #expect(free.listsRemaining == 2)
    #expect(free.placesRemaining == 0, "over the limit never goes negative")
  }

  @Test func chipWording() {
    #expect(Entitlements(proto(plan: "pro", listsLimit: -1, placesLimit: -1)).chipText == "Pro")
    #expect(Entitlements(proto(plan: "free")).chipText == "Free · 3/5 lists · 12/50 places")
    #expect(Entitlements(proto(plan: "free", listsLimit: -1, placesLimit: 50)).chipText == "Free · 12/50 places")
  }

  @MainActor @Test func storeShowsTheCopyFirstThenTheFreshPlanAndKeepsTheCopyOnFailure() async {
    let cache = LocalCache(root: FileManager.default.temporaryDirectory.appending(path: "loci-ent-\(UUID().uuidString)"))
    let fresh = proto(plan: "pro", listsLimit: -1, placesLimit: -1)
    let first = EntitlementsStore(cache: cache, fetch: { fresh })
    #expect(first.current == .free)
    await first.refresh(userID: "u-1")
    #expect(first.current.isPro)
    #expect(first.current.plan == "pro")

    let offline = EntitlementsStore(cache: cache, fetch: { throw APIError.network("down") })
    await offline.refresh(userID: "u-1")
    #expect(offline.current.isPro, "the last known plan stays while the fetch fails")

    let other = EntitlementsStore(cache: cache, fetch: { throw APIError.network("down") })
    await other.refresh(userID: "u-2")
    #expect(other.current == .free, "another account has no copy")

    offline.reset()
    #expect(offline.current == .free)
  }

  @MainActor @Test func storeWithoutAUserStaysFree() async {
    let cache = LocalCache(root: FileManager.default.temporaryDirectory.appending(path: "loci-ent-\(UUID().uuidString)"))
    let store = EntitlementsStore(cache: cache, fetch: { Issue.record("no fetch without a user"); return Loci_Entitlement_V1_Entitlements() })
    await store.refresh(userID: nil)
    #expect(store.current == .free)
  }
}
