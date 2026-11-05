import LociConnectProto
import SwiftUI

/// One card in an answer. Nothing a card offers happens until the tap.
struct AskLociCardView: View {
  let card: AskLociCard
  let turnID: Int
  let controller: AskLociController

  var body: some View {
    switch card {
    case let .trip(proposal, awaitsOwner):
      TripActionCardView(
        proposal: proposal,
        state: controller.state(ofCard: proposal.id),
        // The server checks the trip's version when the card is confirmed.
        canApply: true,
        isSuggestion: awaitsOwner,
        onApply: { option in Task { await controller.confirm(card: proposal.id, turn: turnID, option: option) } },
        onDismiss: { Task { await controller.dismiss(card: proposal.id, turn: turnID) } }
      )
    case let .place(place):
      AskLociPlaceCard(
        summary: place.summary,
        state: controller.state(ofCard: place.id),
        onConfirm: { Task { await controller.confirm(card: place.id, turn: turnID) } },
        onDismiss: { Task { await controller.dismiss(card: place.id, turn: turnID) } }
      )
    case let .handoff(id, query, city):
      AskLociHandoffCard(
        query: query,
        onStart: {
          controller.close()
          AppRouter.shared.open(.plan(prompt: plannerPrompt(query: query, city: city)))
        },
        onDismiss: { controller.dropHandoff(card: id, turn: turnID) }
      )
    case let .note(_, text):
      Text(verbatim: text)
        .font(.lociCaption(14))
        .foregroundStyle(Color.museTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Saving a place. Nothing is saved until Confirm.
private struct AskLociPlaceCard: View {
  let summary: String
  let state: TripActionsModel.CardState
  let onConfirm: () -> Void
  let onDismiss: () -> Void

  private var busy: Bool { state == .applying }

  var body: some View {
    MuseBubble(role: .agent) {
      VStack(alignment: .leading, spacing: 10) {
        Text(verbatim: summary).font(.museBody)
        if case .failed(let text) = state {
          Text(verbatim: text).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive)
        }
        HStack {
          Button(busy ? "Saving…" : "Confirm", action: onConfirm)
            .buttonStyle(MusePillButtonStyle())
            .disabled(busy)
          Button("Not now", action: onDismiss)
            .buttonStyle(MusePillButtonStyle())
            .disabled(busy)
        }
      }
    }
  }
}

/// An offer to plan in the full planner. Nothing has started until the person
/// sends it from the composer, so a search already running is left alone.
private struct AskLociHandoffCard: View {
  let query: String
  let onStart: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    MuseBubble(role: .agent) {
      VStack(alignment: .leading, spacing: 10) {
        Text(verbatim: query).font(.museBody)
        Text("The planner can build this for you.")
          .font(.lociCaption(13))
          .foregroundStyle(Color.museTextSecondary)
        HStack {
          Button("Start planning", action: onStart).buttonStyle(MusePillButtonStyle())
          Button("Not now", action: onDismiss).buttonStyle(MusePillButtonStyle())
        }
      }
    }
  }
}
