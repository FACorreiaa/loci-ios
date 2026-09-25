import Foundation
import LociConnectProto
import Testing

@testable import loci

/// The first-run profile wizard sends what web's trip-setup sends and is offered
/// when web offers it (lib/trip-setup.ts and trip-setup.test.ts, loci-client #82).
@MainActor struct TripSetupTests {
  private let catalogue = [
    TripSetup.Interest(id: "int-food", name: "Food & Dining"),
    TripSetup.Interest(id: "int-art", name: "art & culture"),
    TripSetup.Interest(id: "int-hist", name: "History"),
  ]

  private let serverDefault = TripSetup.ExistingProfile(id: "p-default", name: "Default", isDefault: true)

  private let answers = TripSetup.Answers(budget: 3, pace: .relaxed, mobility: .transit, interests: ["History"])

  // MARK: - Payload

  @Test func sendsInterestIDsNeverLabelsAndDropsWhatTheCatalogueLacks() {
    #expect(TripSetup.interestIDs(for: ["Food & Dining", "Art & Culture", "Nightlife"], catalogue: catalogue) == ["int-food", "int-art"])
    #expect(TripSetup.interestIDs(for: ["Food & Dining", "Food & Dining"], catalogue: catalogue) == ["int-food"])
  }

  @Test func mapsEachChoiceToTheExactEnumTheServerStores() {
    #expect(TripSetup.Pace.relaxed.proto == .relaxed)
    #expect(TripSetup.Pace.moderate.proto == .moderate)
    #expect(TripSetup.Pace.packed.proto == .fast)
    #expect(TripSetup.Mobility.walking.proto == .walk)
    #expect(TripSetup.Mobility.transit.proto == .public)
    #expect(TripSetup.Mobility.car.proto == .car)
    // Step-free is transit plus the accessible flag; WALK would favour long on-foot legs.
    #expect(TripSetup.Mobility.wheelchair.proto == .public)
    let base = TripSetup.Answers(budget: 2, pace: .moderate, mobility: .wheelchair, interests: [])
    #expect(TripSetup.draft(base, catalogue: catalogue).preferAccessible)
    var transit = base
    transit.mobility = .transit
    #expect(!TripSetup.draft(transit, catalogue: catalogue).preferAccessible)
  }

  @Test func mapsEveryPaceAndMobilityChoiceToARealEnumNotAny() {
    for pace in TripSetup.Pace.allCases {
      #expect(pace.proto != .any && pace.proto != .unspecified, "\(pace)")
    }
    for mobility in TripSetup.Mobility.allCases {
      #expect(mobility.proto != .any && mobility.proto != .unspecified, "\(mobility)")
    }
  }

  @Test func buildsTheDefaultProfileTheFirstSearchWillRead() {
    let answers = TripSetup.Answers(budget: 3, pace: .packed, mobility: .wheelchair, interests: ["History"])
    let request = TripSetup.draft(answers, catalogue: catalogue).createRequest()
    #expect(request.profileName == "My Trip Profile")
    #expect(request.isDefault)
    #expect(request.budgetLevel == 3)
    #expect(request.preferredPace == .fast)
    #expect(request.preferredTransport == .public)
    #expect(request.preferAccessiblePois)
    #expect(request.interestIds == ["int-hist"])
  }

  @Test func offersEnoughCuratedInterestsAndChipsFallBackToTheCatalogue() {
    #expect(TripSetup.curatedInterests.count > 5)
    #expect(TripSetup.chips(catalogue: catalogue) == ["Food & Dining", "Art & Culture", "History"])
    let other = [TripSetup.Interest(id: "x", name: "Wine"), TripSetup.Interest(id: "y", name: "Surfing")]
    #expect(TripSetup.chips(catalogue: other) == ["Wine", "Surfing"])
    #expect(TripSetup.chips(catalogue: []).isEmpty)
  }

  // MARK: - Save

  @Test func updatesTheServerCreatedDefaultInsteadOfAddingADuplicate() {
    #expect(TripSetup.save(existing: [serverDefault]) == .update(profileID: "p-default", name: "My Trip Profile"))

    var stored = PreviewTripSetupService.serverDefault
    stored.preferredVibes = []
    let request = TripSetup.draft(answers, catalogue: catalogue, base: TravelProfileDraft(stored), name: "My Trip Profile")
      .updateRequest(id: "p-default")
    #expect(request.profileID == "p-default")
    #expect(request.profileName == "My Trip Profile")
    #expect(request.isDefault)
    #expect(request.budgetLevel == 3)
    #expect(request.preferredPace == .relaxed)
    #expect(request.preferredTransport == .public)
    #expect(request.interestIds == ["int-hist"])
    #expect(request.preferredVibes.isEmpty && request.dietaryNeeds.isEmpty && request.tagIds.isEmpty)
  }

  @Test func keepsTheListsAndNameOfACustomisedDefaultSinceUpdateReplacesLists() {
    var mine = Loci_Profile_UserPreferenceProfile()
    mine.id = "p-mine"
    mine.profileName = "Weekend trips"
    mine.isDefault = true
    mine.preferredVibes = ["cosy"]
    mine.dietaryNeeds = ["vegan"]
    var tag = Loci_Interest_Tags()
    tag.id = "tag-1"
    mine.tags = [tag]
    var food = Loci_Interest_Interest()
    food.id = "int-food"
    mine.interests = [food]

    let existing = [
      TripSetup.ExistingProfile(id: "p-other", name: "Default", isDefault: false),
      TripSetup.ExistingProfile(mine),
    ]
    #expect(TripSetup.save(existing: existing) == .update(profileID: "p-mine", name: "Weekend trips"))

    let request = TripSetup.draft(answers, catalogue: catalogue, base: TravelProfileDraft(mine), name: "Weekend trips")
      .updateRequest(id: "p-mine")
    #expect(request.profileName == "Weekend trips")
    #expect(request.preferredVibes == ["cosy"])
    #expect(request.dietaryNeeds == ["vegan"])
    #expect(request.tagIds == ["tag-1"])
    #expect(request.interestIds == ["int-hist"])
  }

  @Test func createsOnlyWhenThereIsNoDefaultToUpdate() {
    #expect(TripSetup.save(existing: []) == .create)
    var notDefault = serverDefault
    notDefault.isDefault = false
    #expect(TripSetup.save(existing: [notDefault]) == .create)
  }

  @Test func storeUpdatesTheDefaultAndClosesOnlyOnSuccess() async {
    let service = RecordingTripSetupService()
    let store = TripSetupStore(service: service)
    await store.load()
    store.answers = answers
    for _ in TripSetupStore.Step.allCases { await store.next() }
    #expect(store.isDone)
    #expect(service.updates.map(\.profileID) == ["p-default"])
    #expect(service.creates.isEmpty)

    let failing = TripSetupStore(service: PreviewTripSetupService(failsSave: true))
    await failing.save()
    #expect(!failing.isDone)
    #expect(failing.error != nil)
  }

  @Test func aFailedCatalogueNeverTrapsTheUserOnTheLastStep() async {
    let store = TripSetupStore(service: PreviewTripSetupService(failsCatalogue: true))
    await store.load()
    for _ in 0..<3 { await store.next() }
    #expect(store.step == .interests)
    #expect(store.catalogueState == .failed)
    #expect(store.canContinue)

    let loaded = TripSetupStore(service: PreviewTripSetupService())
    await loaded.load()
    for _ in 0..<3 { await loaded.next() }
    #expect(!loaded.canContinue)
    loaded.toggle("History")
    #expect(loaded.canContinue)
  }

  // MARK: - First-run offer

  @Test func treatsTheServersSignUpProfileAsUntouchedAndAnythingChosenAsCustomised() {
    #expect(TripSetup.isUntouched(serverDefault))
    var renamed = serverDefault
    renamed.name = "My Trip Profile"
    #expect(!TripSetup.isUntouched(renamed))
    var withInterest = serverDefault
    withInterest.interestIDs = ["i"]
    #expect(!TripSetup.isUntouched(withInterest))
    var withDiet = serverDefault
    withDiet.dietaryNeeds = ["vegan"]
    #expect(!TripSetup.isUntouched(withDiet))
    #expect(TripSetup.isUntouched(TripSetup.ExistingProfile(PreviewTripSetupService.serverDefault)))
  }

  @Test func offersOnceToNewAccountsWhoseOnlyProfileIsTheServerDefault() {
    let profiles = [serverDefault]
    #expect(TripSetup.shouldOffer(isNewUser: true, seen: false, profiles: profiles))
    // The old gate required zero profiles, which no account ever has.
    #expect(TripSetup.shouldOffer(isNewUser: true, seen: false, profiles: []))
    #expect(!TripSetup.shouldOffer(isNewUser: true, seen: true, profiles: profiles))
    #expect(!TripSetup.shouldOffer(isNewUser: false, seen: false, profiles: profiles))
    var foodTrip = serverDefault
    foodTrip.id = "x"
    foodTrip.name = "Food trip"
    #expect(!TripSetup.shouldOffer(isNewUser: true, seen: false, profiles: [serverDefault, foodTrip]))
  }

  @Test func keysTheSeenFlagByUserSoASecondAccountStillGetsIt() {
    #expect(TripSetup.seenKey(userID: "u1") != TripSetup.seenKey(userID: "u2"))
  }

  @Test func offerPresentsOnceForANewAccountAndNeverReadsForAnExistingOne() async throws {
    let suite = "TripSetupTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let service = RecordingTripSetupService()
    let offer = TripSetupOffer(service: service, defaults: defaults)
    await offer.offerIfNeeded(isNewUser: false, userID: "u1")
    #expect(!offer.isPresenting)
    #expect(service.profileReads == 0)

    await offer.offerIfNeeded(isNewUser: true, userID: "u1")
    #expect(offer.isPresenting)
    offer.dismiss()
    await offer.offerIfNeeded(isNewUser: true, userID: "u1")
    #expect(!offer.isPresenting)

    // A failed profile read never blocks sign-in and never nags.
    let failing = TripSetupOffer(service: RecordingTripSetupService(failsProfiles: true), defaults: defaults)
    await failing.offerIfNeeded(isNewUser: true, userID: "u2")
    #expect(!failing.isPresenting)
  }
}

/// Records writes; its one stored profile is the server's untouched default.
private final class RecordingTripSetupService: TripSetupService, @unchecked Sendable {
  var failsProfiles = false
  private(set) var creates: [Loci_Profile_CreateUserPreferenceProfileRequest] = []
  private(set) var updates: [Loci_Profile_UpdateUserPreferenceProfileRequest] = []
  private(set) var profileReads = 0

  init(failsProfiles: Bool = false) { self.failsProfiles = failsProfiles }

  func catalogue() async throws -> [TripSetup.Interest] { [TripSetup.Interest(id: "int-hist", name: "History")] }
  func profiles() async throws -> [Loci_Profile_UserPreferenceProfile] {
    profileReads += 1
    if failsProfiles { throw APIError.custom("offline") }
    return [PreviewTripSetupService.serverDefault]
  }
  func create(_ request: Loci_Profile_CreateUserPreferenceProfileRequest) async throws { creates.append(request) }
  func update(_ request: Loci_Profile_UpdateUserPreferenceProfileRequest) async throws { updates.append(request) }
}
