import LociConnectProto
import Testing

@testable import loci

actor StubTripActions: TripActionService {
  var applyResult: Result<Loci_Chat_ApplyTripActionResponse, TripActionError> = .success(.init())
  private(set) var applied: [(String, Int?, Int64)] = []
  private(set) var dismissed: [String] = []

  func setApply(_ result: Result<Loci_Chat_ApplyTripActionResponse, TripActionError>) { applyResult = result }

  func apply(proposalID: String, option: Int?, baseVersion: Int64) async throws(TripActionError) -> Loci_Chat_ApplyTripActionResponse {
    applied.append((proposalID, option, baseVersion))
    return try applyResult.get()
  }

  func dismiss(proposalID: String) async throws(TripActionError) {
    dismissed.append(proposalID)
  }
}

@MainActor
struct TripActionsModelTests {
  private func proposal(_ id: String) -> Loci_Chat_ActionProposal {
    var p = Loci_Chat_ActionProposal()
    p.id = id
    p.tripID = "t1"
    return p
  }

  @Test func applySendsTheVersionAndReturnsTheTrip() async {
    let stub = StubTripActions()
    var response = Loci_Chat_ApplyTripActionResponse()
    response.trip.version = 4
    await stub.setApply(.success(response))
    let model = TripActionsModel(service: stub)
    let trip = await model.apply(proposal("p1"), option: 1, baseVersion: 3)
    #expect(trip?.version == 4)
    #expect(model.state("p1") == .applied)
    let calls = await stub.applied
    #expect(calls.first?.0 == "p1" && calls.first?.1 == 1 && calls.first?.2 == 3)
  }

  @Test func aStaleTripKeepsTheCardAndSaysSo() async {
    let stub = StubTripActions()
    await stub.setApply(.failure(TripActionError(kind: .stale, message: "x")))
    let model = TripActionsModel(service: stub)
    let trip = await model.apply(proposal("p1"), option: nil, baseVersion: 3)
    #expect(trip == nil)
    if case .failed(let text) = model.state("p1") { #expect(text.contains("changed")) } else { Issue.record("expected failed") }
    #expect(model.needsReload)
  }

  @Test func noVersionYetAppliesNothing() async {
    let stub = StubTripActions()
    let model = TripActionsModel(service: stub)
    #expect(await model.apply(proposal("p1"), option: nil, baseVersion: nil) == nil)
    #expect(await stub.applied.isEmpty)
  }

  @Test func dismissTellsTheServerAndHidesTheCard() async {
    let stub = StubTripActions()
    let model = TripActionsModel(service: stub)
    await model.dismiss(proposal("p2"))
    #expect(await stub.dismissed == ["p2"])
    #expect(model.state("p2") == .dismissed)
  }
}
