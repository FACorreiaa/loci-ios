import LociConnectProto
import SwiftUI

/// One change the planner proposes (web: components/chat/TripActionCard.tsx).
struct TripActionCardView: View {
  let proposal: Loci_Chat_ActionProposal
  let state: TripActionsModel.CardState
  let canApply: Bool
  /// Someone else's trip: the card is the caller's suggestion, waiting for
  /// the owner, and can only be taken back.
  var isSuggestion = false
  let onApply: (_ option: Int?) -> Void
  let onDismiss: () -> Void

  private var isHotels: Bool { if case .searchHotels = proposal.action.kind { true } else { false } }
  private var isFlight: Bool { if case .searchFlights = proposal.action.kind { true } else { false } }
  private var busy: Bool { state == .applying }

  var body: some View {
    MuseBubble(role: .agent) {
      VStack(alignment: .leading, spacing: 10) {
        Text(proposal.summary).font(.museBody)
        if isSuggestion {
          Text("Sent to the trip's planner. It's on the trip page for everyone to see.")
            .font(.lociCaption(13)).foregroundStyle(Color.museTextSecondary)
        }
        if isHotels, !isSuggestion {
          ForEach(proposal.options.enumerated(), id: \.offset) { index, option in
            Button { onApply(index) } label: {
              VStack(alignment: .leading) {
                Text(option.label)
                if !option.detail.isEmpty { Text(option.detail).font(.lociCaption(12)).foregroundStyle(Color.museTextSecondary) }
              }
            }
            .buttonStyle(MusePillButtonStyle())
            .disabled(busy || !canApply)
          }
        }
        if isFlight, case .flight(let flight)? = proposal.options.first?.choice {
          ForEach(flight.links.filter { $0.url.hasPrefix("https://") }, id: \.url) { link in
            if let url = URL(string: link.url) { Link(link.label, destination: url) }
          }
        }
        if case .failed(let text) = state {
          Text(text).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive)
        }
        HStack {
          if !isSuggestion, !isHotels, !isFlight || !proposal.options.isEmpty {
            Button(canApply ? (busy ? "Updating…" : (isFlight ? "Save to trip" : "Confirm")) : "Loading trip…") {
              onApply(isFlight ? 0 : nil)
            }
            .buttonStyle(MusePillButtonStyle())
            .disabled(busy || !canApply)
          }
          Button(isSuggestion ? "Take back" : "Not now", action: onDismiss).buttonStyle(MusePillButtonStyle()).disabled(busy)
        }
      }
    }
  }
}
