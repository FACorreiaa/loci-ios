import Foundation
import LociConnectProto
import Testing

@testable import loci

struct TripProposalStreamTests {
  private func proposal(_ id: String, event: String) -> Loci_Chat_StreamEvent {
    var e = Loci_Chat_StreamEvent()
    e.eventID = event
    e.actionProposal.proposal.id = id
    e.actionProposal.proposal.summary = "Set dates"
    return e
  }

  @Test func proposalsCollectOncePerProposal() {
    var state = SearchState()
    _ = state.apply(proposal("p1", event: "e1"))
    _ = state.apply(proposal("p2", event: "e2"))
    _ = state.apply(proposal("p1", event: "e3"))  // replayed under a new event id
    #expect(state.proposals.map(\.id) == ["p1", "p2"])
  }

  @MainActor @Test func tripIdGoesOnTheRequestOnlyWhenSet() {
    var envelope = SearchEnvelope(
      sessionId: nil, requestId: "r", profileId: nil, lastEventId: nil, query: "x", cityName: nil, domain: nil,
      latitude: nil, longitude: nil, startedAt: .now, finished: false, notified: false)
    #expect(!SearchSessionController.request(from: envelope, resuming: false).hasTripID)
    envelope.tripId = "t1"
    #expect(SearchSessionController.request(from: envelope, resuming: false).tripID == "t1")
  }
}
