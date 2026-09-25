import Foundation
import Observation

/// The wizard's state: four steps, the answers, the catalogue the interest
/// chips come from, and the one write at the end. A failed save is said out
/// loud with Try again and Skip; nothing pretends it worked.
@MainActor @Observable final class TripSetupStore {
  enum Step: Int, CaseIterable { case budget, pace, mobility, interests }

  private(set) var step = Step.budget
  var answers = TripSetup.Answers()
  private(set) var catalogue: [TripSetup.Interest] = []
  private(set) var isSaving = false
  private(set) var error: String?
  private(set) var isDone = false

  let service: TripSetupService

  init(service: TripSetupService = ConnectTripSetupService()) {
    self.service = service
  }

  var chips: [String] { TripSetup.chips(catalogue: catalogue) }
  var isLast: Bool { step == Step.allCases.last }
  var canContinue: Bool { step != .interests || !answers.interests.isEmpty }
  var progress: Double { Double(step.rawValue + 1) / Double(Step.allCases.count) }

  func load() async {
    catalogue = (try? await service.catalogue()) ?? []
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

  func save() async {
    guard !isSaving else { return }
    isSaving = true
    error = nil
    defer { isSaving = false }
    do {
      try await service.create(TripSetup.draft(answers, catalogue: catalogue).createRequest())
      Analytics.capture(.tripSetupCompleted, ["interests": answers.interests.count, "pace": answers.pace.rawValue])
      isDone = true
    } catch {
      self.error = error.userMessage
    }
  }
}

/// Whether to show the wizard now: once, after a sign-in, to an account with
/// no profile. Web does the same in afterSignInTarget.
@MainActor @Observable final class TripSetupOffer {
  static let shared = TripSetupOffer()
  static let seenKey = "loci_trip_setup_seen"

  var isPresenting = false

  private let service: TripSetupService

  init(service: TripSetupService = ConnectTripSetupService()) {
    self.service = service
  }

  func offerIfNeeded() async {
    let seen = UserDefaults.standard.bool(forKey: Self.seenKey)
    guard !seen else { return }
    // A failed read must never block sign-in or nag: it counts as "unknown".
    let count = try? await service.profileCount()
    guard TripSetup.shouldOffer(seen: seen, profileCount: count) else { return }
    UserDefaults.standard.set(true, forKey: Self.seenKey)
    isPresenting = true
  }

  func dismiss() { isPresenting = false }
}
