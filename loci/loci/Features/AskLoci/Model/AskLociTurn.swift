import Foundation
import LociConnectProto

/// A hotel comparison in an answer, with the trip proposal that came for it.
nonisolated struct AskLociHotelReport: Equatable, Sendable {
  var report: Loci_Chat_HotelComparisonReport
  /// The proposal `report.stay_proposal_id` names: its options are the
  /// report's hotels, so it is the card's Add buttons rather than a second card.
  var proposal: Loci_Chat_ActionProposal?
  /// The caller is a co-planner: the choice went to the trip's owner.
  var awaitsOwner = false
  /// The server's words once a hotel was added.
  var confirmation: String?
}

/// Something the assistant put in front of the person to answer.
nonisolated enum AskLociCard: Equatable, Sendable, Identifiable {
  case trip(Loci_Chat_ActionProposal, awaitsOwner: Bool)
  case hotelReport(AskLociHotelReport)
  case place(Loci_Assistant_PlaceAction)
  case handoff(id: String, query: String, city: String?)
  /// What a card became once the person answered it.
  case note(id: String, text: String)

  var id: String {
    switch self {
    case let .trip(proposal, _): proposal.id
    case let .hotelReport(card): "hotel-report-\(card.report.id)"
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
      case let .trip(trip):
        if !fold(trip, awaitsOwner: proposal.awaitsOwner) { cards.append(.trip(trip, awaitsOwner: proposal.awaitsOwner)) }
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
    case let .hotelReport(report):
      addHotelReport(report)
    case nil:
      break
    }
  }

  /// A trip proposal that belongs to a report already on the turn goes into
  /// that report's card. False when it is a card of its own.
  private mutating func fold(_ proposal: Loci_Chat_ActionProposal, awaitsOwner: Bool) -> Bool {
    guard !proposal.id.isEmpty else { return false }
    for index in cards.indices {
      guard case .hotelReport(var card) = cards[index], card.report.stayProposalID == proposal.id else { continue }
      card.proposal = proposal
      card.awaitsOwner = awaitsOwner
      cards[index] = .hotelReport(card)
      return true
    }
    return false
  }

  /// The report, taking its proposal with it if that arrived first. A report
  /// sent again (same id) replaces the one shown.
  private mutating func addHotelReport(_ report: Loci_Chat_HotelComparisonReport) {
    guard !report.hotels.isEmpty else { return }
    var card = AskLociHotelReport(report: report)
    if !report.stayProposalID.isEmpty,
      let index = cards.firstIndex(where: { if case .trip(let trip, _) = $0 { trip.id == report.stayProposalID } else { false } }),
      case let .trip(trip, awaitsOwner) = cards[index]
    {
      card.proposal = trip
      card.awaitsOwner = awaitsOwner
      cards.remove(at: index)
    }
    if let index = cards.firstIndex(where: { $0.id == AskLociCard.hotelReport(card).id }) {
      if case .hotelReport(let shown) = cards[index], card.proposal == nil {
        card.proposal = shown.proposal
        card.awaitsOwner = shown.awaitsOwner
        card.confirmation = shown.confirmation
      }
      cards[index] = .hotelReport(card)
    } else {
      cards.append(.hotelReport(card))
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
      // A report outlives its proposal: confirmed, it says so and stays; turned
      // down, it goes back to asking which trip.
      if case .hotelReport(var report) = card, report.proposal?.id == cardID {
        if let note { report.confirmation = note } else { report.proposal = nil }
        return .hotelReport(report)
      }
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
