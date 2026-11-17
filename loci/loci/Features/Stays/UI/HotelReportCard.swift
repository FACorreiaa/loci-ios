import LociConnectProto
import SwiftUI

/// A hotel report with its "Add … to trip" wired up, for either chat.
///
/// With the server's stay proposal, a tap applies that hotel's option through
/// the chat's own path (the caller's `apply`). Without one, or once that
/// proposal has failed, a tap asks which trip and calls SetStay with the
/// hotel's ready-made stay.
struct HotelReportCard: View {
  /// The proposal `stay_proposal_id` names, and how this chat applies it.
  struct Proposal {
    let tripID: String
    let state: TripActionsModel.CardState
    let apply: (_ option: Int) -> Void
  }

  let report: Loci_Chat_HotelComparisonReport
  let surface: HotelCompareSurface
  var proposal: Proposal?
  /// The caller is a co-planner: the choice went to the trip's owner.
  var sentToOwner = false
  /// The server's words once the proposal was applied.
  var confirmation: String?
  /// False on a result page, which is already inside the agent's bubble.
  var inBubble = true
  var onOpenTrip: (String) -> Void = { AppRouter.shared.open(.trip(id: $0)) }
  var onPlan: (String) -> Void = { AppRouter.shared.open(.plan(prompt: $0)) }
  var service: StayService = ConnectStayService()

  private struct Picking: Identifiable {
    let id: Int
  }

  private struct Picked {
    let tripID: String
    let message: String
  }

  @State private var picking: Picking?
  @State private var picked: Picked?
  /// The hotel last tapped, so the busy button and the confirmation name it.
  @State private var tapped: Int?

  static let sentNotice = String(localized: "Sent to the trip's planner. It's on the trip page for everyone to see.")

  private var names: [String] { HotelReport.names(report) }

  /// Where Add stands: the trip picker's result first, else the proposal's.
  static func addState(
    picked: String?,
    proposal: TripActionsModel.CardState?,
    tapped: Int?,
    names: [String],
    confirmation: String?
  ) -> HotelReportAddState {
    if let picked { return .added(picked) }
    switch proposal {
    case .applying: return .adding(tapped ?? 0)
    case .applied:
      if let confirmation, !confirmation.isEmpty { return .added(confirmation) }
      let hotel = tapped.flatMap { names.indices.contains($0) ? names[$0] : nil }
      return .added(hotel.map { HotelReport.addedMessage(hotel: $0, trip: "") } ?? String(localized: "Added to your trip."))
    case .failed(let text): return .failed(text)
    case .ready, .dismissed, nil: return .ready
    }
  }

  private var addState: HotelReportAddState {
    Self.addState(picked: picked?.message, proposal: proposal?.state, tapped: tapped, names: names, confirmation: confirmation)
  }

  private var openTripID: String? { picked?.tripID ?? (proposal?.state == .applied ? proposal?.tripID : nil) }

  var body: some View {
    Group {
      if inBubble { MuseBubble(role: .agent) { card } } else { card }
    }
    .sheet(item: $picking) { choice in pickerSheet(choice.id) }
    .task(id: report.id) { HotelCompareAnalytics.reportShown(surface, report, hasProposal: proposal != nil) }
    .onChange(of: proposal?.state == .applied) { _, applied in
      guard applied else { return }
      HotelCompareAnalytics.staySet(surface, via: .proposal, hotel: tapped.flatMap { report.hotels.indices.contains($0) ? report.hotels[$0] : nil })
    }
    .sensoryFeedback(.success, trigger: openTripID)
  }

  private var card: some View {
    HotelReportCardView(
      report: report,
      add: addState,
      notice: sentToOwner && picked == nil ? Self.sentNotice : nil,
      onAdd: add,
      onOpenTrip: openTripID.map { id in { onOpenTrip(id) } }
    )
  }

  private func add(_ index: Int) {
    guard report.hotels.indices.contains(index) else { return }
    // A proposal that failed (expired, or the trip moved on) is not tried
    // again: the traveller picks the trip instead.
    let usable = proposal.flatMap { $0.state == .ready ? $0 : nil }
    HotelCompareAnalytics.addTapped(
      surface,
      via: usable == nil ? .picker : .proposal,
      option: index,
      recommended: HotelReport.recommendedIndex(report) == index
    )
    tapped = index
    if let usable { usable.apply(index) } else { picking = Picking(id: index) }
  }

  private func pickerSheet(_ index: Int) -> some View {
    let hotel = report.hotels[index]
    return StayTripPickerSheet(
      store: StayTripPickerStore(stay: hotel.stay, hotelName: names[index], service: service),
      onAdded: { trip in
        picked = Picked(tripID: trip.id, message: HotelReport.addedMessage(hotel: names[index], trip: AddToTripPayload.tripTitle(trip)))
        // An open trip page reads the trip again.
        AskLociController.shared.tripChanged()
        HotelCompareAnalytics.staySet(surface, via: .picker, hotel: hotel)
      },
      onOpenTrip: onOpenTrip,
      onPlan: { onPlan(StayTripPicker.planPrompt(city: hotel.stay.cityName)) }
    )
  }
}

/// The report on the Assistant tab's result page and in the trip's planner
/// sheet: the proposal is applied with ApplyTripAction, against the trip's
/// version read the moment before.
struct ChatHotelReportCard: View {
  let report: Loci_Chat_HotelComparisonReport
  /// The search's proposals; the one the report names becomes its Add buttons.
  let proposals: [Loci_Chat_ActionProposal]
  var surface = HotelCompareSurface.chat
  var inBubble = false

  var body: some View {
    let proposal = HotelReport.stayProposal(for: report, in: proposals)
    HotelReportCard(
      report: report,
      surface: surface,
      proposal: proposal.map { proposal in
        let actions = TripActionsModel.forTrip(proposal.tripID)
        return HotelReportCard.Proposal(tripID: proposal.tripID, state: actions.state(proposal.id)) { option in
          Task { await Self.apply(proposal, option: option, actions: actions) }
        }
      },
      inBubble: inBubble
    )
  }

  private static func apply(_ proposal: Loci_Chat_ActionProposal, option: Int, actions: TripActionsModel) async {
    let applied = await actions.applyReadingVersion(proposal, option: option) {
      try? await TripAPI.trip(id: proposal.tripID).version
    }
    if applied { AskLociController.shared.tripChanged() }
  }
}
