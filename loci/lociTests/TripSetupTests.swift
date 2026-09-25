import Foundation
import LociConnectProto
import Testing

@testable import loci

/// The first-run profile wizard sends what web's trip-setup sends (lib/trip-setup.ts):
/// catalogue ids for interests, real pace and transport enums, one default profile.
@MainActor struct TripSetupTests {
  private let catalogue = [
    TripSetup.Interest(id: "int-food", name: "Food & Dining"),
    TripSetup.Interest(id: "int-art", name: "art & culture"),
    TripSetup.Interest(id: "int-hist", name: "History"),
  ]

  @Test func sendsInterestIDsNeverLabelsAndDropsWhatTheCatalogueLacks() {
    #expect(TripSetup.interestIDs(for: ["Food & Dining", "Art & Culture", "Nightlife"], catalogue: catalogue) == ["int-food", "int-art"])
    #expect(TripSetup.interestIDs(for: ["Food & Dining", "Food & Dining"], catalogue: catalogue) == ["int-food"])
  }

  @Test func everyChoiceMapsToARealEnum() {
    for pace in TripSetup.Pace.allCases {
      #expect(pace.proto != .any && pace.proto != .unspecified, "\(pace)")
    }
    for mobility in TripSetup.Mobility.allCases {
      #expect(mobility.proto != .any && mobility.proto != .unspecified, "\(mobility)")
    }
    #expect(TripSetup.Pace.packed.proto == .fast)
    #expect(TripSetup.Mobility.transit.proto == .public)
    #expect(TripSetup.Mobility.wheelchair.proto == .walk)
  }

  @Test func buildsTheDefaultProfileTheFirstSearchWillRead() {
    let answers = TripSetup.Answers(budget: 3, pace: .packed, mobility: .wheelchair, interests: ["History"])
    let draft = TripSetup.draft(answers, catalogue: catalogue)
    #expect(draft.name == "My Trip Profile")
    #expect(draft.isDefault)
    #expect(draft.budgetLevel == 3)
    #expect(draft.preferredPace == .fast)
    #expect(draft.preferredTransport == .walk)
    #expect(draft.preferAccessible)
    #expect(draft.interestIDs == ["int-hist"])
    let request = draft.createRequest()
    #expect(request.interestIds == ["int-hist"])
    #expect(request.isDefault)
  }

  @Test func chipsAreTheCuratedLabelsTheCatalogueHasOrTheCatalogueItself() {
    #expect(TripSetup.chips(catalogue: catalogue) == ["Food & Dining", "Art & Culture", "History"])
    let other = [TripSetup.Interest(id: "x", name: "Wine"), TripSetup.Interest(id: "y", name: "Surfing")]
    #expect(TripSetup.chips(catalogue: other) == ["Wine", "Surfing"])
    #expect(TripSetup.chips(catalogue: []).isEmpty)
  }

  @Test func offeredOnceNotWhenSeenNotWhenProfilesExist() {
    #expect(TripSetup.shouldOffer(seen: false, profileCount: 0))
    #expect(!TripSetup.shouldOffer(seen: true, profileCount: 0))
    #expect(!TripSetup.shouldOffer(seen: false, profileCount: 2))
    // A failed profile read never blocks sign-in and never nags.
    #expect(!TripSetup.shouldOffer(seen: false, profileCount: nil))
  }
}
