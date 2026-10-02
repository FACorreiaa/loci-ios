import LociConnectProto
import SwiftUI

/// The trip's plan: dates, where it sleeps in each city, flights
/// (web: components/trip/TripPlanPanel.tsx). Edits go back to the editor,
/// which sends them with the trip's version and raises the conflict alert.
struct TripPlanSection: View {
  let trip: Loci_Trip_TripDraft
  let onSetDates: (_ start: String, _ end: String) -> Void
  let onSetStay: (Loci_Trip_TripStay) -> Void
  let onAddFlight: (Loci_Trip_TripFlight) -> Void
  let onRemoveFlight: (_ flightID: String) -> Void

  @State private var start = Date()
  @State private var end = Date()
  @State private var stars: [String: Int] = [:]
  @State private var found: [String: [Loci_Favorites_V1_HotelDetails]] = [:]
  @State private var searching: Set<String> = []
  @State private var searched: Set<String> = []
  @State private var search = FlightSearch()
  @State private var links: [Loci_Trip_FlightLink] = []
  @State private var error: String?

  var body: some View {
    Section {
      datesRow
      ForEach(TripPlan.cities(of: trip), id: \.self) { city in stayRow(city) }
      ForEach(trip.flights, id: \.id) { flight in flightRow(flight) }
      flightForm
      if let error { Text(error).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive) }
    } header: {
      Text("Plan").lociCoordStyle(11)
    }
    // Keyed on the dates, not onAppear: a change applied from the planner or a
    // reload after a conflict must reach the pickers, or "Save dates" would put
    // the old ones back.
    .task(id: "\(trip.startDate)|\(trip.endDate)") { seedDates() }
  }

  private func seedDates() {
    if let range = TripPlan.dates(of: trip) {
      start = range.start
      end = range.end
    }
    // The Departs picker shows a date, so the search must hold one too, or
    // "Search flights" stays disabled under a form that looks complete.
    if search.departDate.isEmpty { search.departDate = TripPlan.defaultDeparture(of: trip, today: Date()) }
  }

  private var datesRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      DatePicker("Starts", selection: $start, displayedComponents: .date)
      DatePicker("Ends", selection: $end, in: start..., displayedComponents: .date)
      Button("Save dates") { onSetDates(CalendarMath.dateKey(start), CalendarMath.dateKey(end)) }.buttonStyle(.borderless)
    }.font(.lociBody(15))
  }

  @ViewBuilder private func stayRow(_ city: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(city).font(.lociHeadline(15))
        Spacer()
        if let stay = TripPlan.stay(for: city, in: trip) {
          Text(stay.starRating.isEmpty ? stay.name : "\(stay.name) · \(stay.starRating)★").font(.lociCaption(13))
        } else {
          Text("No hotel yet").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        }
      }
      if let at = TripPlan.coordinate(of: city, in: trip) {
        HStack {
          Picker("Stars", selection: Binding(get: { stars[city] ?? 0 }, set: { stars[city] = $0 })) {
            Text("Any").tag(0)
            Text("3★").tag(3)
            Text("4★").tag(4)
            Text("5★").tag(5)
          }.pickerStyle(.segmented)
          Button(searching.contains(city) ? "Searching…" : "Find") { Task { await findHotels(city, at) } }.disabled(searching.contains(city))
            .buttonStyle(.borderless)
        }
        ForEach(found[city] ?? [], id: \.id) { hotel in
          Button {
            pick(hotel, in: city)
          } label: {
            Text(hotel.starRating.isEmpty ? hotel.name : "\(hotel.name) · \(hotel.starRating)★")
          }.buttonStyle(.borderless)
        }
        if searched.contains(city), (found[city] ?? []).isEmpty {
          let wanted = stars[city] ?? 0
          Text(wanted > 0 ? "No \(wanted)★ hotels within 5 km. Try any stars." : "No hotels found within 5 km.")
            .font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
        }
      } else {
        Text("Can't search hotels in \(city): the trip has no map position for it yet.").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
      }
    }
  }

  private func findHotels(_ city: String, _ at: (latitude: Double, longitude: Double)) async {
    searching.insert(city)
    defer { searching.remove(city) }
    do {
      let hotels = try await TripPlanAPI.hotelsNear(latitude: at.latitude, longitude: at.longitude)
      found[city] = Array(TripPlan.hotels(hotels, stars: stars[city] ?? 0).prefix(5))
      searched.insert(city)
      error = nil
    } catch { self.error = "Couldn't look up hotels in \(city) right now." }
  }

  private func pick(_ hotel: Loci_Favorites_V1_HotelDetails, in city: String) {
    var stay = Loci_Trip_TripStay()
    stay.cityName = city
    stay.poiID = hotel.id
    stay.name = hotel.name
    if let value = TripPlan.stars(hotel.starRating) { stay.starRating = value == value.rounded() ? String(Int(value)) : String(value) }
    if hotel.website.hasPrefix("https://") { stay.bookingURL = hotel.website }
    found[city] = []
    onSetStay(stay)
  }

  private func flightRow(_ flight: Loci_Trip_TripFlight) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(flight.origin.name) → \(flight.destination.name) · \(flight.departDate)").font(.lociBody(15))
      HStack(spacing: 12) {
        ForEach(flight.links.filter { $0.url.hasPrefix("https://") }, id: \.url) { link in
          if let url = URL(string: link.url) { Link(link.label, destination: url).font(.lociCaption(13)) }
        }
        Spacer()
        Button("Remove", role: .destructive) { onRemoveFlight(flight.id) }.buttonStyle(.borderless).font(.lociCaption(13))
      }
    }
  }

  private var flightForm: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("From (city or airport)", text: $search.origin)
      TextField("To", text: $search.destination)
      DatePicker(
        "Departs",
        selection: Binding(get: { CalendarMath.parseDateKey(search.departDate) ?? start }, set: { search.departDate = CalendarMath.dateKey($0) }),
        displayedComponents: .date
      )
      Toggle(
        "Return flight",
        isOn: Binding(
          get: { search.returnDate != nil },
          set: { search.returnDate = $0 ? (search.departDate.isEmpty ? CalendarMath.dateKey(end) : search.departDate) : nil }
        )
      )
      if search.returnDate != nil {
        DatePicker(
          "Returns",
          selection: Binding(
            get: { CalendarMath.parseDateKey(search.returnDate ?? "") ?? end },
            set: { search.returnDate = CalendarMath.dateKey($0) }
          ),
          displayedComponents: .date
        )
      }
      Stepper("Travellers: \(search.passengers)", value: $search.passengers, in: 1...9)
      HStack {
        Button("Search flights") { Task { await buildLinks() } }.disabled(!search.isReady).buttonStyle(.borderless)
        Spacer()
        if !links.isEmpty {
          Button("Save to trip") {
            onAddFlight(search.flight)
            links = []
          }.buttonStyle(.borderless)
        }
      }
      ForEach(links.filter { $0.url.hasPrefix("https://") }, id: \.url) { link in
        if let url = URL(string: link.url) { Link(link.label, destination: url).font(.lociCaption(13)) }
      }
      Text("Prices are on the airline sites; Loci only saves your search.").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
    }.font(.lociBody(15))
  }

  private func buildLinks() async {
    do {
      links = try await TripPlanAPI.flightLinks(search)
      error = nil
    } catch { self.error = error.message }
  }
}
