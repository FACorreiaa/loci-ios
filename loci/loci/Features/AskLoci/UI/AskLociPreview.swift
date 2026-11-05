import LociConnectProto
import SwiftUI

/// `-designPreview askLoci…`: the overlay on sample turns. It has its own
/// controller and a plain backdrop: a signed-out launch resets the shared one, and
/// the tabs behind it would raise their own network errors.
struct AskLociPreview: View {
  var turns: [AskLociTurn] = []
  var mic: DictationController.State?

  @State private var controller = AskLociController()

  var body: some View {
    Color.lociPaper
      .ignoresSafeArea()
      .overlay { AskLociOverlay(controller: controller) }
      .onAppear { controller.preview(turns: turns, mic: mic) }
  }

  static var thinking: [AskLociTurn] {
    var turn = AskLociTurn(id: 1, you: "What's the weather like for my Porto trip?")
    turn.status = "Checking your trips"
    return [turn]
  }

  static var cards: [AskLociTurn] {
    var first = AskLociTurn(id: 1, you: "Which of my friends has been to Porto?")
    first.reply = "Ana was there in March and saved Livraria Lello and Majestic Café."
    first.done = true

    var second = AskLociTurn(id: 2, you: "Save Majestic Café, and swap tomorrow's lunch for it")
    second.reply = "Here's what I'd do. Nothing changes until you confirm."
    var place = Loci_Assistant_PlaceAction()
    place.id = "place"
    place.summary = "Save Majestic Café to your favourites"
    var proposal = Loci_Chat_ActionProposal()
    proposal.id = "trip"
    proposal.summary = "Replace Tuesday's lunch with Majestic Café"
    second.cards = [
      .place(place),
      .trip(proposal, awaitsOwner: false),
      .handoff(id: "handoff-2", query: "Plan 3 more days in Porto", city: "Porto"),
      .note(id: "note", text: "Saved Livraria Lello."),
    ]
    second.done = true
    second.reason = .interrupted
    return [first, second]
  }
}
