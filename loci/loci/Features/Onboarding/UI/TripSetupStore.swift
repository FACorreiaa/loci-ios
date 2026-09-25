import Foundation
import LociConnectProto
import Observation

/// The wizard's state: four steps, the answers, the catalogue the interest
/// chips come from, and the one write at the end. A failed save is said out
/// loud with Try again and Skip; nothing pretends it worked, and the cover
/// closes only on success or a skip.
@MainActor @Observable final class TripSetupStore {
  enum Step: Int, CaseIterable {
    case budget, pace, mobility, interests

    /// The analytics name, and web's step label in lower case.
    var name: String {
      switch self {
      case .budget: "budget"
      case .pace: "pace"
      case .mobility: "getting_around"
      case .interests: "interests"
      }
    }
  }

  enum Catalogue: Equatable {
    case loading
    case loaded([TripSetup.Interest])
    case failed
  }

  private(set) var step = Step.budget
  var answers = TripSetup.Answers()
  private(set) var catalogueState = Catalogue.loading
  private(set) var isSaving = false
  private(set) var error: String?
  private(set) var isDone = false

  let service: TripSetupService

  init(service: TripSetupService = ConnectTripSetupService()) {
    self.service = service
  }

  var catalogue: [TripSetup.Interest] {
    if case .loaded(let interests) = catalogueState { return interests }
    return []
  }
  var chips: [String] { TripSetup.chips(catalogue: catalogue) }
  var isLast: Bool { step == Step.allCases.last }
  /// Interests are required only when there is a catalogue to pick from; a
  /// failed load must not trap the user on the last step (web: canNext).
  var canContinue: Bool { step != .interests || !answers.interests.isEmpty || chips.isEmpty }
  var progress: Double { Double(step.rawValue + 1) / Double(Step.allCases.count) }

  func load() async {
    catalogueState = .loading
    do {
      catalogueState = .loaded(try await service.catalogue())
    } catch {
      catalogueState = .failed
    }
  }

  func toggle(_ interest: String) {
    if let index = answers.interests.firstIndex(of: interest) {
      answers.interests.remove(at: index)
    } else {
      answers.interests.append(interest)
    }
  }

  func back() {
    if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
  }

  /// Next step, or the save on the last one.
  func next() async {
    if let following = Step(rawValue: step.rawValue + 1) {
      step = following
      return
    }
    await save()
  }

  /// Update the server-created default profile (or create one when there is
  /// none), re-reading the profiles so the lists sent back are current.
  func save() async {
    guard !isSaving else { return }
    isSaving = true
    error = nil
    defer { isSaving = false }
    do {
      let stored = try await service.profiles()
      switch TripSetup.save(existing: stored.map(TripSetup.ExistingProfile.init)) {
      case .create:
        try await service.create(TripSetup.draft(answers, catalogue: catalogue).createRequest())
      case let .update(id, name):
        let base = stored.first { $0.id == id }.map(TravelProfileDraft.init) ?? TravelProfileDraft(isDefault: true)
        try await service.update(TripSetup.draft(answers, catalogue: catalogue, base: base, name: name).updateRequest(id: id))
      }
      Analytics.capture(.onboardingCompleted, ["skipped": false, "step": step.name])
      isDone = true
    } catch {
      self.error = error.userMessage
    }
  }

  func skip() {
    Analytics.capture(.onboardingCompleted, ["skipped": true, "step": step.name])
    isDone = true
  }
}

/// Whether to show the wizard now: once per account on this phone, right
/// after the sign-in that created it, while its only profile is still the
/// server's untouched "Default". Web does the same in afterSignInTarget.
@MainActor @Observable final class TripSetupOffer {
  static let shared = TripSetupOffer()

  var isPresenting = false

  private let service: TripSetupService
  private let defaults: UserDefaults

  init(service: TripSetupService = ConnectTripSetupService(), defaults: UserDefaults = .standard) {
    self.service = service
    self.defaults = defaults
  }

  /// Existing accounts cost no RPC. A failed profile read never blocks
  /// sign-in or nags: it just doesn't offer.
  func offerIfNeeded(isNewUser: Bool, userID: String?) async {
    guard isNewUser, let userID, !userID.isEmpty else { return }
    let key = TripSetup.seenKey(userID: userID)
    let seen = defaults.bool(forKey: key)
    guard !seen, let stored = try? await service.profiles() else { return }
    let profiles = stored.map(TripSetup.ExistingProfile.init)
    guard TripSetup.shouldOffer(isNewUser: isNewUser, seen: seen, profiles: profiles) else { return }
    // Seen counts from the first look, finished or not.
    defaults.set(true, forKey: key)
    isPresenting = true
  }

  func dismiss() { isPresenting = false }
}
