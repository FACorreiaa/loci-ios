import LociConnectProto
import SwiftUI

/// A text field with airport suggestions (web: components/flights/AirportField.tsx).
/// Typing is free text, sent as a name; picking a suggestion attaches its IATA
/// code, which is what Skyscanner needs.
struct AirportField: View {
  let title: String
  @Binding var text: String
  @Binding var iata: String?

  @State private var options: [Loci_Trip_FlightPlaceOption] = []
  /// The text a pick wrote, so the change it causes does not search again.
  @State private var picked: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField(title, text: $text)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .onChange(of: text) { _, new in
          if new != picked { iata = nil }
        }
      ForEach(options, id: \.iata) { option in
        Button {
          let label = Self.label(option)
          picked = label
          text = label
          iata = option.iata
          options = []
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(Self.label(option)).font(.lociBody(15))
            if option.kind == .airport {
              Text("\(option.name) · \(option.countryCode)").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
            }
          }
        }
        .buttonStyle(.borderless)
        .accessibilityHint("Uses this airport")
      }
    }
    // Debounced by the task restarting on each keystroke.
    .task(id: text) {
      guard text != picked, text.trimmingCharacters(in: .whitespaces).count >= 2 else {
        options = []
        return
      }
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      options = (try? await TripPlanAPI.searchAirports(text)) ?? []
    }
  }

  /// "Lisbon (LIS)", or "London (all airports)" for a metro code.
  static func label(_ o: Loci_Trip_FlightPlaceOption) -> String {
    o.kind == .metro ? o.name : "\(o.city.isEmpty ? o.name : o.city) (\(o.iata))"
  }
}
