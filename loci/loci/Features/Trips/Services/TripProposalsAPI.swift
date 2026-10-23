import Foundation
import LociConnectProto

/// Planning together's suggestions (web: lib/api/trip-proposals.ts): a
/// co-planner suggests a stop edit, everyone on the trip reacts, and the owner
/// applies or turns it down through `TripActionService`, the same RPCs the
/// planner's chat cards use.
nonisolated enum TripProposalsAPI {
  private static var client: Loci_Chat_ChatServiceClient {
    Loci_Chat_ChatServiceClient(client: ConnectTransport.shared.protocolClient)
  }

  /// The trip's open suggestions, newest first, for anyone on it.
  static func list(tripID: String) async throws -> [Loci_Chat_ActionProposal] {
    var request = Loci_Chat_ListTripProposalsRequest()
    request.tripID = tripID
    return try await rpc("Could not load the suggestions.", request) {
      await client.listTripProposals(request: $0, headers: [:])
    }.proposals
  }

  /// Sends a stop edit to the trip's owner. Co-planners only.
  static func propose(tripID: String, baseVersion: Int64, action: Loci_Chat_TripAction) async throws -> Loci_Chat_ActionProposal {
    var request = Loci_Chat_ProposeTripChangeRequest()
    request.tripID = tripID
    request.baseVersion = baseVersion
    request.action = action
    return try await rpc("Couldn't send that suggestion.", request) { await client.proposeTripChange(request: $0, headers: [:]) }
  }

  /// 1 for 👍, -1 for 👎, 0 takes the reaction back.
  static func react(proposalID: String, value: Int32) async throws -> Loci_Chat_ActionProposal {
    var request = Loci_Chat_ReactToTripProposalRequest()
    request.proposalID = proposalID
    request.value = value
    return try await rpc("Couldn't save that.", request) { await client.reactToTripProposal(request: $0, headers: [:]) }
  }
}

/// The stop edits a co-planner can suggest, as the proto's TripAction.
nonisolated enum SuggestedChange {
  case add(dayID: String, stop: Loci_Trip_TripStop)
  case remove(stopID: String)
  case replace(stopID: String, with: Loci_Trip_TripStop)
  case move(stopID: String, toDayID: String, toIndex: Int)

  var action: Loci_Chat_TripAction {
    var action = Loci_Chat_TripAction()
    switch self {
    case let .add(dayID, stop):
      var add = Loci_Chat_AddStopAction()
      add.dayID = dayID
      add.stop = stop
      action.addStop = add
    case .remove(let stopID):
      var remove = Loci_Chat_RemoveStopAction()
      remove.stopID = stopID
      action.removeStop = remove
    case let .replace(stopID, stop):
      var replace = Loci_Chat_ReplaceStopAction()
      replace.stopID = stopID
      replace.replacement = stop
      action.replaceStop = replace
    case let .move(stopID, toDayID, toIndex):
      var move = Loci_Chat_MoveStopAction()
      move.stopID = stopID
      move.toDayID = toDayID
      move.toIndex = Int32(toIndex)
      action.moveStop = move
    }
    return action
  }

  /// Where `List.onMove` puts a single row: the offset is "insert before",
  /// counted before the row is taken out.
  static func moveIndex(from: Int, toOffset: Int) -> Int { toOffset > from ? toOffset - 1 : toOffset }
}
