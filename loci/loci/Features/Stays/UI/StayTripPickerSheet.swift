import LociConnectProto
import SwiftUI

/// "Which trip?" for a hotel from a comparison report, when the server could
/// not tell (web: components/chat/HotelTripPicker.tsx). Trips that go to the
/// hotel's city can take it; the others are listed, greyed, with the reason.
/// With none, it offers to plan a trip there.
struct StayTripPickerSheet: View {
  @State private var store: StayTripPickerStore
  let onAdded: (Loci_Trip_TripDraft) -> Void
  let onOpenTrip: (String) -> Void
  let onPlan: () -> Void
  @Environment(\.dismiss) private var dismiss

  init(
    store: StayTripPickerStore,
    onAdded: @escaping (Loci_Trip_TripDraft) -> Void,
    onOpenTrip: @escaping (String) -> Void,
    onPlan: @escaping () -> Void
  ) {
    _store = State(initialValue: store)
    self.onAdded = onAdded
    self.onOpenTrip = onOpenTrip
    self.onPlan = onPlan
  }

  var body: some View {
    NavigationStack {
      List {
        if let trip = store.added { addedSection(trip) } else { content }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background { Color.lociPaper.ignoresSafeArea() }
      .navigationTitle("Add to trip")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(store.added == nil ? "Cancel" : "Done") { dismiss() } }
      }
      .errorAlert($store.error)
      .task { await store.load() }
      .sensoryFeedback(.success, trigger: store.added != nil)
      .onAppear { Analytics.screen("hotel_report_trip_picker") }
    }
    .adaptiveDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder private var content: some View {
    switch store.phase {
    case .loading:
      Section { ProgressView().frame(maxWidth: .infinity) } header: { Text(verbatim: store.hotelName) }
        .listRowBackground(Color.lociCard)
    case .failed(let message):
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text(message).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          Button("Try again") { Task { await store.load() } }
        }
      } header: {
        Text(verbatim: store.hotelName)
      }
      .listRowBackground(Color.lociCard)
    case .loaded:
      if !store.hasEligibleTrip { planSection }
      if !store.options.isEmpty { tripsSection }
    }
  }

  private var planSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 10) {
        Text(store.options.isEmpty ? "You have no trips yet." : "None of your trips goes to \(Text(verbatim: store.cityName)).")
          .font(.lociBody(15)).foregroundStyle(Color.lociInk)
        Text("Plan one and add \(Text(verbatim: store.hotelName)) from this report afterwards.")
          .font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        Button {
          dismiss()
          onPlan()
        } label: {
          Text("Plan a \(Text(verbatim: store.cityName)) trip")
        }
        .lociProminentButton()
      }
      .padding(.vertical, 4)
    }
    .listRowBackground(Color.lociCard)
  }

  private var tripsSection: some View {
    Section {
      ForEach(store.options) { option in row(option) }
    } header: {
      Text("Make \(Text(verbatim: store.hotelName)) your stay on")
    }
    .listRowBackground(Color.lociCard)
  }

  private func row(_ option: StayTripOption) -> some View {
    let busy = store.addingTripID == option.id
    return Button {
      Task {
        guard await store.add(to: option.id), let trip = store.added else { return }
        onAdded(trip)
      }
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: AddToTripPayload.tripTitle(option.trip))
            .font(.lociBody(15))
            .foregroundStyle(option.isEligible ? Color.lociInk : Color.lociMutedInk)
          if !option.isEligible {
            Text(verbatim: StayTripPicker.reason(city: store.cityName)).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
          } else if let stay = TripPlan.stay(for: store.cityName, in: option.trip) {
            Text("Replaces \(Text(verbatim: stay.name))").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
          }
        }
        Spacer(minLength: 8)
        if busy { ProgressView() }
      }
      .frame(minHeight: LociTheme.minTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!option.isEligible || store.addingTripID != nil)
  }

  private func addedSection(_ trip: Loci_Trip_TripDraft) -> some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        Label("Stay saved", systemImage: "checkmark.circle.fill")
          .font(.lociHeadline(17))
          .foregroundStyle(Color.lociForest)
        Text(verbatim: HotelReport.addedMessage(hotel: store.hotelName, trip: AddToTripPayload.tripTitle(trip)))
          .font(.lociBody(15)).foregroundStyle(Color.lociInk)
        Text("The trip now shows how to get around from it.")
          .font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        Button("Open trip", systemImage: "arrow.right") {
          dismiss()
          onOpenTrip(trip.id)
        }
        .lociProminentButton()
      }
      .padding(.vertical, 4)
    }
    .listRowBackground(Color.lociCard)
  }
}
