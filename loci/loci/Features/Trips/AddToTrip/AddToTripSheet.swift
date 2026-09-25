import LociConnectProto
import SwiftUI

/// Add a place to one of your trips (web: AddToTripButton's popover): a trip,
/// a day, "Add to Day N". Stays open on success with "Open trip". With no
/// trips it offers to start one for this city, or to open Trips.
struct AddToTripSheet: View {
  @State var store: AddToTripStore
  @State private var route: Route?
  @Environment(\.dismiss) private var dismiss

  enum Route: Hashable {
    case trip(String)
    case trips
  }

  init(store: AddToTripStore) {
    _store = State(initialValue: store)
  }

  init(stop: Loci_Poi_POIDetailedInfo, cityName: String) {
    let service: AddToTripService = ResultsSideData.isOffline ? PreviewAddToTripService() : ConnectAddToTripService()
    self.init(store: AddToTripStore(poi: stop, cityName: cityName, service: service))
  }

  var body: some View {
    NavigationStack {
      List {
        if let added = store.added {
          addedSection(added)
        } else {
          content
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle("Add to trip")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(store.added == nil ? "Cancel" : "Done") { dismiss() } }
      }
      .safeAreaInset(edge: .bottom) { addBar }
      .navigationDestination(item: $route) { route in
        switch route {
        case .trip(let id): TripEditorView(tripID: id)
        case .trips: TripsView()
        }
      }
      .errorAlert($store.error)
      .task { await store.load() }
      .sensoryFeedback(.success, trigger: store.added != nil)
      .onAppear { Analytics.screen("add_to_trip") }
    }
    .adaptiveDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder private var content: some View {
    switch store.phase {
    case .loading:
      Section { ProgressView().frame(maxWidth: .infinity) } header: { Text(store.placeName) }
        .listRowBackground(Color.lociCard)
    case .failed(let message):
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text(message).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          Button("Try again") { Task { await store.load() } }
        }
      } header: {
        Text(store.placeName)
      }
      .listRowBackground(Color.lociCard)
    case .loaded:
      if store.trips.isEmpty { noTrips } else { pickers }
    }
  }

  private var noTrips: some View {
    Section {
      ContentUnavailableView {
        Label("No trips yet", systemImage: "suitcase")
      } description: {
        Text("Start one and \(store.placeName) goes on Day 1.")
      } actions: {
        Button {
          Task { await store.createTrip(userID: AuthSessionManager.shared.currentUserID) }
        } label: {
          if store.isCreating {
            ProgressView()
          } else {
            Text(store.newTripCity.isEmpty ? "Create a trip" : "Create a \(store.newTripCity) trip")
          }
        }
        .lociProminentButton()
        .disabled(store.isCreating)
        Button("Open Trips") { route = .trips }
          .tint(Color.lociForest)
      }
    }
    .listRowBackground(Color.lociCard)
  }

  @ViewBuilder private var pickers: some View {
    Section {
      Picker("Trip", selection: $store.selectedTripID) {
        ForEach(store.trips, id: \.id) { trip in
          Text(AddToTripPayload.tripTitle(trip)).tag(Optional(trip.id))
        }
      }
      .pickerStyle(.menu)
      .tint(Color.lociForest)
    } header: {
      Text("Add \(store.placeName) to")
    }
    .listRowBackground(Color.lociCard)

    if let trip = store.selectedTrip {
      Section("Day") {
        if trip.days.isEmpty {
          Text("This trip has no days yet. Open it to add one.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        }
        ForEach(trip.days, id: \.dayNumber) { day in
          Button {
            store.selectedDayNumber = day.dayNumber
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(AddToTripPayload.dayLabel(day, tripCity: trip.cityName)).font(.lociBody(15)).foregroundStyle(Color.lociInk)
                Text(AddToTripPayload.stopCount(day)).lociCoordStyle(9)
              }
              Spacer(minLength: 8)
              if store.selectedDayNumber == day.dayNumber {
                Image(systemName: "checkmark").foregroundStyle(Color.lociForest).accessibilityHidden(true)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(store.selectedDayNumber == day.dayNumber ? .isSelected : [])
        }
      }
      .listRowBackground(Color.lociCard)
    }
  }

  private func addedSection(_ added: AddedStop) -> some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        Label(AddToTripPayload.addedMessage(dayNumber: added.dayNumber), systemImage: "checkmark.circle.fill")
          .font(.lociHeadline(17))
          .foregroundStyle(Color.lociForest)
        Text("\(store.placeName) is in \(AddToTripPayload.tripTitle(added.trip)).")
          .font(.lociBody(15)).foregroundStyle(Color.lociInk)
        Button("Open trip", systemImage: "arrow.right") { route = .trip(added.trip.id) }
          .lociProminentButton()
      }
      .padding(.vertical, 4)
    }
    .listRowBackground(Color.lociCard)
  }

  @ViewBuilder private var addBar: some View {
    if store.added == nil, store.phase == .loaded, !store.trips.isEmpty {
      Button {
        Task { await store.add() }
      } label: {
        Group {
          if store.isAdding {
            ProgressView().tint(.white)
          } else {
            Text(store.selectedDay.map { "Add to Day \($0.dayNumber)" } ?? "Pick a day")
          }
        }
        .frame(maxWidth: .infinity)
      }
      .lociProminentButton()
      .controlSize(.large)
      .disabled(!store.canAdd)
      .padding(.horizontal, LociTheme.defaultPadding).padding(.vertical, 10)
      .background(Color.lociPaper)
    }
  }
}
