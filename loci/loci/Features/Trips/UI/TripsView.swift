import Connect
import LociConnectProto
import SwiftUI

public struct TripsView: View {
  @State private var trips: [Loci_Trip_TripDraft] = []
  @State private var isLoading: Bool = false
  @State private var errorMessage: String?

  private let client: Loci_Trip_TripServiceClient

  public init(client: Loci_Trip_TripServiceClient = Loci_Trip_TripServiceClient(client: ConnectTransport.shared.protocolClient)) {
    self.client = client
  }

  public var body: some View {
    NavigationStack {
      VStack {
        if isLoading {
          Spacer()
          ProgressView()
          Spacer()
        } else if let errorMessage {
          Spacer()
          VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.lociCoral)
            Text(errorMessage).font(.subheadline).foregroundColor(.lociInk.opacity(0.7))
            Button("Try Again") { loadTrips() }.foregroundColor(.lociCoral)
          }.padding()
          Spacer()
        } else if trips.isEmpty {
          Spacer()
          VStack(spacing: 16) {
            Image("LociMascot").resizable().scaledToFit().frame(width: 96, height: 96)

            Text("No Trips Planned Yet").font(.title3.weight(.bold)).foregroundColor(.lociInk)

            Text("Start a conversation in Chat or discover places to build your first tailored itinerary.").font(.subheadline).foregroundColor(
              .lociInk.opacity(0.7)
            ).multilineTextAlignment(.center).padding(.horizontal, 36)
          }
          Spacer()
        } else {
          List(trips, id: \.id) { trip in
            VStack(alignment: .leading, spacing: 6) {
              Text(trip.title.isEmpty ? (trip.cityName.isEmpty ? "Untitled Trip" : "Trip to \(trip.cityName)") : trip.title).font(
                .headline.weight(.semibold)
              ).foregroundColor(.lociInk)

              HStack {
                if !trip.cityName.isEmpty { Label(trip.cityName, systemImage: "mappin.circle.fill").font(.caption).foregroundColor(.lociCoral) }
                Spacer()
                Text("\(trip.days.count) days").font(.caption.weight(.medium)).foregroundColor(.lociInk.opacity(0.6))
              }
            }.padding(.vertical, 8).listRowBackground(Color.lociCard)
          }.listStyle(.insetGrouped).scrollContentBackground(.hidden)
        }
      }.background(Color.lociPaper.ignoresSafeArea()).navigationTitle("My Trips").toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            loadTrips()
          } label: {
            Image(systemName: "arrow.clockwise")
          }
        }
      }
    }.task { loadTrips() }
  }

  private func loadTrips() {
    isLoading = true
    errorMessage = nil
    Task {
      var headers: Connect.Headers = [:]
      if let token = try? await AuthSessionManager.shared.validAccessToken() { headers["Authorization"] = ["Bearer \(token)"] }

      let response = await client.listTrips(request: Loci_Trip_ListTripsRequest(), headers: headers)
      await MainActor.run {
        self.isLoading = false
        if let error = response.error { self.errorMessage = error.message } else if let message = response.message { self.trips = message.trips }
      }
    }
  }
}
