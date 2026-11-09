import LociConnectProto
import SwiftUI

/// Flights to a page's city (web: components/flights/FindFlightsDialog.tsx):
/// the destination is resolved to its airport (or metro code) and shown, the
/// traveller says where they fly from — every time, nothing is stored — and
/// gets partner searches to book on.
struct FindFlightsSheet: View {
  let source: FlightSource
  let city: String
  var latitude: Double?
  var longitude: Double?
  /// YYYY-MM-DD, from a dated trip.
  var startDate: String?
  var endDate: String?

  @Environment(\.dismiss) private var dismiss
  @State private var search = FlightSearch()
  @State private var resolved = false

  var body: some View {
    NavigationStack {
      Form {
        if resolved {
          FlightSearchForm(source: source, search: $search) { _ in EmptyView() }
        } else {
          ProgressView("Finding the airport…")
        }
      }
      .navigationTitle("Flights to \(city)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
    .task {
      guard !resolved else { return }
      search.departDate = startDate ?? ""
      search.returnDate = endDate
      let option = try? await TripPlanAPI.resolveDestination(city: city, latitude: latitude, longitude: longitude)
      if let option {
        search.destination = AirportField.label(option)
        search.destinationIATA = option.iata
      } else {
        search.destination = city
      }
      resolved = true
      FlightAnalytics.opened(source, destinationIATA: option?.iata)
    }
  }
}

/// The entry point on a results page or a trip: a pill that opens the sheet.
struct FindFlightsButton: View {
  let source: FlightSource
  let city: String
  var latitude: Double?
  var longitude: Double?
  var startDate: String?
  var endDate: String?
  @State private var open = false

  var body: some View {
    Button("Find flights to \(city)", systemImage: "airplane") { open = true }
      .sheet(isPresented: $open) {
        FindFlightsSheet(
          source: source,
          city: city,
          latitude: latitude,
          longitude: longitude,
          startDate: startDate,
          endDate: endDate
        )
      }
  }
}

/// The trip's entry, a row in its Plan section: its first city, that city's
/// position and the trip's dates.
struct TripFindFlightsRow: View {
  let trip: Loci_Trip_TripDraft

  var body: some View {
    if let city = TripPlan.cities(of: trip).first {
      let at = TripPlan.coordinate(of: city, in: trip)
      FindFlightsButton(
        source: .trip,
        city: city,
        latitude: at?.latitude,
        longitude: at?.longitude,
        startDate: trip.startDate.isEmpty ? nil : trip.startDate,
        endDate: trip.endDate.isEmpty ? nil : trip.endDate
      )
    }
  }
}
