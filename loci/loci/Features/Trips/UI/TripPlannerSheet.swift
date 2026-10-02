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
  @State private var actions: TripActionsModel
  @State private var startError: String?
  @State private var confirmReplace = false
  private var controller: SearchSessionController { .shared }

  init(
    trip: Loci_Trip_TripDraft,
    currentVersion: @escaping () -> Int64?,
    onTripChanged: @escaping (Loci_Trip_TripDraft) -> Void,
    onReloadTrip: @escaping () async -> Void
  ) {
    self.trip = trip
    self.currentVersion = currentVersion
    self.onTripChanged = onTripChanged
    self.onReloadTrip = onReloadTrip
    _actions = State(initialValue: .forTrip(trip.id))
  }

  /// Asking starts a search, and the controller runs one at a time. Replacing
  /// one about something else (a Discover search, another trip) is the
  /// traveller's call, as it is in the search composer.
  static func replacesAnotherSearch(isActive: Bool, runningTripId: String?, tripId: String) -> Bool {
    isActive && runningTripId != tripId
  }

  /// The controller is shared with every other search: what it holds is this
  /// sheet's only while its search is about this trip.
  private var isOurs: Bool { controller.currentTripId == trip.id }

  private var failure: String? {
    guard isOurs, case .failed(let text) = controller.state.status, text != SearchState.stoppedMessage else { return nil }
    return text
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Text("Ask for dates, hotels, more days or flights for \(trip.title).")
            .font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
          ForEach(actions.cards, id: \.id) { proposal in
            TripActionCardView(
              proposal: proposal,
              state: actions.state(proposal.id),
              canApply: currentVersion() != nil,
              onApply: { option in Task { await apply(proposal, option) } },
              onDismiss: { Task { await actions.dismiss(proposal) } }
            )
          }
          if let error = startError ?? failure {
            Text(error).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive)
          }
          if isOurs, controller.state.isActive { ProgressView() }
          if isOurs, let link = controller.startedLink {
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
      .onAppear(perform: collect)
      .onChange(of: controller.state.proposals) { _, _ in collect() }
      .confirmationDialog("A search is still running. Replace it?", isPresented: $confirmReplace, titleVisibility: .visible) {
        Button("Ask the planner instead", role: .destructive) { Task { await send() } }
      }
    }
  }

  private var composer: some View {
    HStack {
      TextField("12 to 15 Nov, 4-star hotels…", text: $message, axis: .vertical)
        .textFieldStyle(.roundedBorder)
      Button("Send") {
        if Self.replacesAnotherSearch(isActive: controller.state.isActive, runningTripId: controller.currentTripId, tripId: trip.id) {
          confirmReplace = true
        } else {
          Task { await send() }
        }
      }
      .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (isOurs && controller.state.isActive))
    }
    .padding(LociTheme.defaultPadding)
    .background(Color.lociPaper)
  }

  /// Cards that arrived, including while the sheet was closed.
  private func collect() {
    guard isOurs else { return }
    actions.collect(controller.state.proposals, forTrip: trip.id)
  }

  private func send() async {
    let text = message
    message = ""
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
