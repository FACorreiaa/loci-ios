import LociConnectProto
import SwiftUI

/// "Ask the planner": a chat about this trip whose turns propose changes as
/// cards (the agent never changes the trip without a tap). A turn that is a
/// normal answer instead offers to open it.
struct TripPlannerSheet: View {
  let trip: Loci_Trip_TripDraft
  /// The trip's version now, for the card's base_version; nil while loading.
  let currentVersion: () -> Int64?
  let onTripChanged: (Loci_Trip_TripDraft) -> Void
  let onReloadTrip: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var message = ""
  @State private var actions = TripActionsModel()
  /// The controller is shared with every other search; nothing it holds is
  /// this sheet's until the sheet has asked something itself.
  @State private var asked = false
  @State private var startError: String?
  private var controller: SearchSessionController { .shared }

  private var proposals: [Loci_Chat_ActionProposal] {
    guard asked else { return [] }
    return controller.state.proposals.filter {
      $0.tripID == trip.id && actions.state($0.id) != .applied && actions.state($0.id) != .dismissed
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Text("Ask for dates, hotels, more days or flights for \(trip.title).")
            .font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
          ForEach(proposals, id: \.id) { proposal in
            TripActionCardView(
              proposal: proposal,
              state: actions.state(proposal.id),
              canApply: currentVersion() != nil,
              onApply: { option in Task { await apply(proposal, option) } },
              onDismiss: { Task { await actions.dismiss(proposal) } }
            )
          }
          if let startError {
            Text(startError).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive)
          }
          if asked, controller.state.status == .streaming { ProgressView() }
          if asked, let link = controller.startedLink {
            Button("See the answer") { dismiss(); AppRouter.shared.open(link) }
              .buttonStyle(MusePillButtonStyle())
          }
        }
        .padding(LociTheme.defaultPadding)
      }
      .safeAreaInset(edge: .bottom) { composer }
      .navigationTitle("Planner")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
  }

  private var composer: some View {
    HStack {
      TextField("12 to 15 Nov, 4-star hotels…", text: $message, axis: .vertical)
        .textFieldStyle(.roundedBorder)
      Button("Send") { Task { await send() } }
        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (asked && controller.state.status == .streaming))
    }
    .padding(LociTheme.defaultPadding)
    .background(Color.lociPaper)
  }

  private func send() async {
    let text = message
    message = ""
    asked = true
    startError = nil
    do {
      try await controller.start(query: text, cityName: trip.cityName, tripId: trip.id)
    } catch {
      startError = error.localizedDescription
    }
  }

  private func apply(_ proposal: Loci_Chat_ActionProposal, _ option: Int?) async {
    if let next = await actions.apply(proposal, option: option, baseVersion: currentVersion()) {
      onTripChanged(next)
    } else if actions.needsReload {
      await onReloadTrip()
      actions.reloaded()
    }
  }
}
