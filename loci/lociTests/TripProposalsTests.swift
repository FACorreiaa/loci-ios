import Foundation
import LociConnectProto
import Testing

@testable import loci

struct TripProposalsTests {
  @Test(arguments: [
    (0, 2, 1),  // down one: "insert before" the row after next
    (0, 3, 2),  // to the end of three
    (2, 0, 0),  // to the top
    (1, 1, 1),  // dropped where it was
  ])
  func moveIndex(from: Int, toOffset: Int, expected: Int) {
    #expect(SuggestedChange.moveIndex(from: from, toOffset: toOffset) == expected)
  }

  @Test func changesBecomeTripActions() {
    var stop = Loci_Trip_TripStop()
    stop.name = "Pastéis de Belém"

    guard case .addStop(let add)? = SuggestedChange.add(dayID: "d1", stop: stop).action.kind else {
      Issue.record("not an add")
      return
    }
    #expect(add.dayID == "d1")
    #expect(add.stop.name == "Pastéis de Belém")

    guard case .moveStop(let move)? = SuggestedChange.move(stopID: "s1", toDayID: "d2", toIndex: 3).action.kind else {
      Issue.record("not a move")
      return
    }
    #expect(move.stopID == "s1" && move.toDayID == "d2" && move.toIndex == 3)

    guard case .replaceStop(let swap)? = SuggestedChange.replace(stopID: "s1", with: stop).action.kind else {
      Issue.record("not a swap")
      return
    }
    #expect(swap.replacement.name == "Pastéis de Belém")
    if case .removeStop(let remove)? = SuggestedChange.remove(stopID: "s9").action.kind {
      #expect(remove.stopID == "s9")
    } else {
      Issue.record("not a remove")
    }
  }

  @Test func bylineAndPick() {
    var suggestion = Loci_Chat_ActionProposal()
    suggestion.source = .editor
    var ana = Loci_Social_PublicUser()
    ana.displayName = "Ana"
    suggestion.proposer = ana
    #expect(TripProposalsSection.byline(suggestion) == "Ana suggests")

    var hotels = Loci_Chat_ActionProposal()
    hotels.source = .chat
    hotels.action.searchHotels = Loci_Chat_SearchHotelsAction()
    #expect(TripProposalsSection.byline(hotels) == "From the trip planner")
    #expect(TripProposalsSection.needsPick(hotels))
    #expect(!TripProposalsSection.needsPick(suggestion))
  }

  @Test func applyErrorsOnTheTripPage() {
    #expect(TripActionError(kind: .stale, message: "").tripPageMessage.contains("just changed"))
    #expect(TripActionError(kind: .invalid, message: "").tripPageMessage.contains("no longer on the trip"))
  }
}
