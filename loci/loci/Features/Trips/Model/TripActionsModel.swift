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

  func dismiss(_ proposal: Loci_Chat_ActionProposal) async {
    states[proposal.id] = .dismissed
    try? await service.dismiss(proposalID: proposal.id)  // a courtesy to the server; the card goes either way
  }

  func reloaded() { needsReload = false }
}
