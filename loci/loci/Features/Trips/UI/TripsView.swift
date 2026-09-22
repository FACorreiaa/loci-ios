import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Trips (web: /trips). TripService.ListTrips; rows open the editor (/trips/:id).
public struct TripsView: View {
  @State private var trips: [Loci_Trip_TripDraft] = []
  @State private var isLoading = true
  @State private var error: String?

  public init() {}

  public var body: some View {
    List {
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

  private func load() async {
    var request = Loci_Trip_ListTripsRequest()
    request.pagination.page = 1
    request.pagination.pageSize = 50
    do {
      trips = try await rpc("Could not load your trips.", request) { await TripAPI.client.listTrips(request: $0, headers: [:]) }.trips
    } catch { self.error = error.userMessage }
    isLoading = false
  }
}

/// The trip client, shared by the list, the editor and Compare's save.
nonisolated enum TripAPI {
  static let client = Loci_Trip_TripServiceClient(client: ConnectTransport.shared.protocolClient)
}
