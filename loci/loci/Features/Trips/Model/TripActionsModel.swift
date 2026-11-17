import Foundation
import LociConnectProto
import Observation

/// The state of the planner's proposal cards (web: TripActionCard). Nothing
/// changes until the traveller taps; the server applies a proposal once,
/// against the trip version the card was shown with.
@MainActor @Observable final class TripActionsModel {
  enum CardState: Equatable { case ready, applying, failed(String), applied, dismissed }

  private(set) var states: [String: CardState] = [:]
  /// Set when a card met a stale trip: the sheet reloads the trip's version.
  private(set) var needsReload = false
  private let service: TripActionService

  init(service: TripActionService = ConnectTripActionService()) {
    self.service = service
  }

  func state(_ id: String) -> CardState { states[id] ?? .ready }

  /// Every card this trip's planner turns proposed, in arrival order. Kept
  /// here, not read off the stream: each turn starts a fresh stream state, and
  /// a card must not vanish because the traveller asked something else.
  private(set) var collected: [Loci_Chat_ActionProposal] = []

  /// The cards still waiting for a tap.
  var cards: [Loci_Chat_ActionProposal] {
    collected.filter { state($0.id) != .applied && state($0.id) != .dismissed }
  }

  func collect(_ proposals: [Loci_Chat_ActionProposal], forTrip tripId: String) {
    for proposal in proposals where proposal.tripID == tripId && !collected.contains(where: { $0.id == proposal.id }) {
      collected.append(proposal)
    }
  }

  private static var byTrip: [String: TripActionsModel] = [:]

  /// One model per trip for the app's lifetime, so closing the planner while a
  /// turn is still running does not lose the cards it brings.
  static func forTrip(_ tripId: String) -> TripActionsModel {
    if let model = byTrip[tripId] { return model }
    let model = TripActionsModel()
    byTrip[tripId] = model
    return model
  }

  /// The trip as it now is, or nil when nothing changed. `baseVersion` is nil
  /// until the trip has loaded; a card cannot be applied before that.
  func apply(_ proposal: Loci_Chat_ActionProposal, option: Int?, baseVersion: Int64?) async -> Loci_Trip_TripDraft? {
    guard let baseVersion, state(proposal.id) != .applying else { return nil }
    states[proposal.id] = .applying
    do {
      let response = try await service.apply(proposalID: proposal.id, option: option, baseVersion: baseVersion)
      states[proposal.id] = .applied
      return response.hasTrip ? response.trip : nil
    } catch {
      states[proposal.id] = .failed(error.userMessage)
      if error.kind == .stale { needsReload = true }
      return nil
    }
  }

  /// Apply from a card shown away from the trip page (a hotel report in the
  /// main chat), where no loaded trip supplies the version: read it, apply,
  /// and if the trip moved in between, read and apply once more. True once
  /// the proposal is applied.
  func applyReadingVersion(_ proposal: Loci_Chat_ActionProposal, option: Int?, version: () async -> Int64?) async -> Bool {
    for _ in 0..<2 {
      guard let current = await version() else {
        states[proposal.id] = .failed("Couldn't load the trip. Try again.")
        return false
      }
      _ = await apply(proposal, option: option, baseVersion: current)
      if state(proposal.id) == .applied { return true }
      guard needsReload else { return false }
      needsReload = false
    }
    return false
  }

  func dismiss(_ proposal: Loci_Chat_ActionProposal) async {
    states[proposal.id] = .dismissed
    try? await service.dismiss(proposalID: proposal.id)  // a courtesy to the server; the card goes either way
  }

  func reloaded() { needsReload = false }
}
