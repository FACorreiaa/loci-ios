import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Trips (web: /trips). TripService.ListTrips; rows open the editor (/trips/:id).
public struct TripsView: View {
  @State private var trips: [Loci_Trip_TripDraft] = []
  @State private var loaded: Loaded<Loci_Trip_ListTripsResponse>?
  @State private var isLoading = true
  @State private var error: String?

  public init() {}

  public var body: some View {
    List {
      if let loaded, loaded.staleSince != nil {
        Section { CacheChip(loaded: loaded) }.listRowBackground(Color.clear)
      }
      ForEach(trips, id: \.id) { trip in
        NavigationLink(value: trip.id) {
          VStack(alignment: .leading, spacing: 3) {
            Text(trip.title.isEmpty ? trip.cityName : trip.title).font(.lociHeadline()).foregroundStyle(Color.lociInk)
            HStack {
              Text(trip.cityName)
              Text("\(trip.days.count) day\(trip.days.count == 1 ? "" : "s")")
              if trip.hasUpdatedAt { Text(trip.updatedAt.date, style: .date) }
            }
            .lociCoordStyle(10)
          }
        }
      }
    }
    .overlay {
      if !isLoading, trips.isEmpty {
        ContentUnavailableView("No trips yet", systemImage: "suitcase", description: Text("Save an itinerary or a compare result and it lands here."))
      }
    }
    .settingsStyle("My trips")
    .navigationDestination(for: String.self) { TripEditorView(tripID: $0) }
    .refreshable { await load() }
    .errorAlert($error)
    .task { await load() }
  }

  /// The phone's copy first, then the server; offline keeps the copy and says so.
  private func load() async {
    isLoading = trips.isEmpty
    var request = Loci_Trip_ListTripsRequest()
    request.pagination.page = 1
    request.pagination.pageSize = 50
    let sent = request
    loaded = await cacheThrough(Loci_Trip_ListTripsResponse.self, kind: .trips, id: "all", onCached: { trips = $0.value.trips }) {
      try await rpc("Could not load your trips.", sent) { await TripAPI.client.listTrips(request: $0, headers: [:]) }
    }
    if let value = loaded?.value { trips = value.trips } else if case .missing(let reason) = loaded { error = reason.userMessage }
    if case .fresh = loaded { TripPrefetch.scheduleIfNeeded(trips: trips) }
    isLoading = false
  }
}

/// The trip client, shared by the list, the editor and Compare's save.
nonisolated enum TripAPI {
  static let client = Loci_Trip_TripServiceClient(client: ConnectTransport.shared.protocolClient)
}
