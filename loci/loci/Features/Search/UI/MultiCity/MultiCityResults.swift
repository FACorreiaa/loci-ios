import LociConnectProto
import SwiftUI

/// A search's results. One city is ResultsPage as it always was; several are
/// a city picker over each city's own ResultsPage, with "All days" showing
/// every city in turn and the travel between them.
struct MultiCityResults: View {
  let state: SearchState
  var onRerun: (String) -> Void = { _ in }
  @State private var selection: Int?

  var body: some View {
    if state.isMultiCity {
      VStack(alignment: .leading, spacing: 12) {
        StopPicker(stops: state.stops, selection: $selection)
        if let outline = state.route?.outline, !outline.isEmpty {
          Text(outline).font(.caption).foregroundStyle(.secondary)
        }
        if let dropped = state.route?.dropped, !dropped.isEmpty {
          Text("Left out: " + dropped.map { "\($0.cityName) (\($0.reason))" }.joined(separator: "; "))
            .font(.caption2).foregroundStyle(.secondary)
        }
        if let index = selection, let stop = state.stops.first(where: { $0.index == index }) {
          city(stop)
        } else {
          ForEach(state.stops, id: \.index) { stop in
            Text(stop.cityName).font(.title3.weight(.semibold)).padding(.top, 8)
            city(stop)
            if let leg = legAfter(stop) { LegRowView(leg: leg) }
          }
        }
      }
    } else {
      ResultsPage(state: state, onRerun: onRerun)
    }
  }

  @ViewBuilder private func city(_ stop: StopResult) -> some View {
    if let error = stop.error {
      FailureRail(message: error, canRetry: true) { onRerun("\(state.query) in \(stop.cityName)") }
    } else {
      ResultsPage(state: stop.state, onRerun: onRerun)
    }
  }

  /// The move out of this city: the leg that leaves on its last day.
  private func legAfter(_ stop: StopResult) -> Loci_Trip_TripLeg? {
    guard let last = stop.dayNumbers.last else { return nil }
    return state.route?.legs.first { $0.fromName == stop.cityName && Int($0.afterDay) == last }
  }
}
