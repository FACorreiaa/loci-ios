import Foundation

/// Where an App Intent takes the app, as the deep link the router already
/// opens (`AppLink`), so Siri and a tapped link land in the same place.
nonisolated enum IntentRoute: Equatable {
  case planDay(city: String)
  case nearbyFits

  static func url(for route: IntentRoute) -> URL {
    var components = URLComponents()
    components.scheme = "loci"
    switch route {
    case .planDay(let city):
      let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
      components.host = "plan"
      components.queryItems = [URLQueryItem(name: "q", value: city.isEmpty ? "Plan a day" : "Plan a day in \(city)")]
    case .nearbyFits:
      components.host = "nearby"
    }
    // Scheme and host are fixed ASCII, so the URL always forms.
    return components.url ?? URL(fileURLWithPath: "/")
  }
}
