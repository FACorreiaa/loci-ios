import Foundation
import LociConnectProto

/// Something the assistant put in front of the person to answer.
nonisolated enum AskLociCard: Equatable, Sendable, Identifiable {
  case trip(Loci_Chat_ActionProposal, awaitsOwner: Bool)
  case place(Loci_Assistant_PlaceAction)
  case handoff(id: String, query: String, city: String?)
  /// What a card became once the person answered it.
  case note(id: String, text: String)

  var id: String {
    switch self {
    case let .trip(proposal, _): proposal.id
    case let .place(place): place.id
    case let .handoff(id, _, _): id
    case let .note(id, _): id
    }
  }
}

/// One question and everything that came back for it
/// (web: loci-client/src/lib/assistant/turns.ts).
nonisolated struct AskLociTurn: Equatable, Sendable, Identifiable {
  let id: Int
  let you: String
  var reply = ""
  /// What the assistant is doing right now, written by the server.
  var status: String?
  var cards: [AskLociCard] = []
  var done = false
  var reason: Loci_Assistant_DoneReason?
  var degraded = false
  /// Why nothing could be sent or heard, for the person to read.
  var failure: String?
  /// The assistant is switched off here, so point at the chat, which isn't.
  var offerChat = false

  init(id: Int, you: String) {
    self.id = id
    self.you = you
  }

  /// The turn after one event.
  mutating func apply(_ event: Loci_Assistant_AssistantEvent) {
    switch event.event {
    case let .textDelta(delta):
      reply += delta.text
      status = nil
    case let .toolStatus(tool):
      status = tool.label
    case let .proposal(proposal):
      switch proposal.kind {
      case let .trip(trip): cards.append(.trip(trip, awaitsOwner: proposal.awaitsOwner))
      case let .place(place): cards.append(.place(place))
      case nil: break
      }
    case let .handoff(handoff):
      cards.append(
        .handoff(
          id: "handoff-\(cards.count)",
          query: handoff.query,
          city: handoff.hasCity ? handoff.city : nil
        )
      )
    case let .done(finished):
      done = true
      status = nil
      reason = finished.reason
      degraded = finished.degraded
    case nil:
      break
    }
  }

  /// The line under an answer when something about it needs saying.
  var closingNote: String? {
    if let failure { return failure }
    guard done else { return nil }
    switch reason {
    case .interrupted: return "That answer stopped part way."
    case .dailyLimit: return "That's all the questions for today. Ask again tomorrow."
    case .refused: return "I can't help with that one."
    case .unavailable: return "I can't answer right now. Try again in a moment."
    default: return degraded ? "I can't check your details or change anything right now." : nil
    }
  }

  /// A card has been answered: it becomes the note, or goes if there is none.
  mutating func settleCard(_ cardID: String, note: String?) {
    cards = cards.compactMap { card in
      guard card.id == cardID else { return card }
      return note.map { .note(id: cardID, text: $0) }
    }
  }
}

/// What the planner receives from a handoff. The tool asks for the person's own
/// words, which may not name the city.
nonisolated func plannerPrompt(query: String, city: String?) -> String {
  guard let city, !city.isEmpty, !query.lowercased().contains(city.lowercased()) else { return query }
  return "\(query) in \(city)"
}
