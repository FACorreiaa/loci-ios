import LociConnectProto
import SwiftUI

/// The flight search fields, shared by the trip's Plan section and the Find
/// flights sheet (web: components/flights/FlightSearchForm.tsx). It builds
/// partner search links on the server (no prices) and counts what it does.
struct FlightSearchForm<Extra: View>: View {
  let source: FlightSource
  @Binding var search: FlightSearch
  /// Seeds for the date pickers when the search has none yet.
  var defaultDepart = Date()
  var defaultReturn = Date()
  /// Shown beside "Search flights" once links exist (the Plan's Save).
  @ViewBuilder var extra: (FlightSearch) -> Extra

  @State private var links: [Loci_Trip_FlightLink] = []
  @State private var builtFor: FlightSearch?
  @State private var error: String?
  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      AirportField(title: "From (city or airport)", text: $search.origin, iata: $search.originIATA)
      AirportField(title: "To", text: $search.destination, iata: $search.destinationIATA)
      DatePicker(
        "Departs",
        selection: Binding(
          get: { CalendarMath.parseDateKey(search.departDate) ?? defaultDepart },
          set: { search.departDate = CalendarMath.dateKey($0) }
        ),
        displayedComponents: .date
      )
      Toggle(
        "Return flight",
        isOn: Binding(
          get: { search.returnDate != nil },
          set: { search.returnDate = $0 ? (search.departDate.isEmpty ? CalendarMath.dateKey(defaultReturn) : search.departDate) : nil }
        )
      )
      if search.returnDate != nil {
        DatePicker(
          "Returns",
          selection: Binding(
            get: { CalendarMath.parseDateKey(search.returnDate ?? "") ?? defaultReturn },
            set: { search.returnDate = CalendarMath.dateKey($0) }
          ),
          displayedComponents: .date
        )
      }
      Stepper("Travellers: \(search.passengers)", value: $search.passengers, in: 1...9)
      HStack {
        Button("Search flights") { Task { await buildLinks() } }.disabled(!search.isReady).buttonStyle(.borderless)
        Spacer()
        if !links.isEmpty, let builtFor { extra(builtFor) }
      }
      ForEach(links.filter { $0.url.hasPrefix("https://") }, id: \.url) { link in
        if let url = URL(string: link.url) {
          Button(link.sponsored ? "\(link.label) · partner link" : link.label) {
            FlightAnalytics.clicked(source, link, builtFor)
            openURL(url)
          }
          .buttonStyle(.borderless)
          .font(.lociCaption(13))
          .accessibilityHint("Opens \(link.label) in the browser")
        }
      }
      if let error { Text(error).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive) }
      Text("Prices are on the airline sites; Loci only builds your search.").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
    }
    .font(.lociBody(15))
  }

  private func buildLinks() async {
    let s = search
    do {
      links = try await TripPlanAPI.flightLinks(s)
      builtFor = s
      error = nil
      FlightAnalytics.built(source, s)
    } catch {
      self.error = error.message
    }
  }
}
