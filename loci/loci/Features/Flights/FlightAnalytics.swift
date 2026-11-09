import Foundation
import LociConnectProto

/// Where a flight search was opened from; the same values web sends.
nonisolated enum FlightSource: String, Sendable {
  case itinerary, hotels, restaurants, activities, trip, chat
}

/// Flight search usage, the same three events and properties web sends
/// (loci-client src/lib/flights/analytics.ts). Codes only: nothing the
/// traveller typed leaves the device.
enum FlightAnalytics {
  static func opened(_ source: FlightSource, destinationIATA: String?) {
    Analytics.capture(.flightSearchOpened, openedProperties(source, destinationIATA: destinationIATA))
  }

  static func built(_ source: FlightSource, _ search: FlightSearch) {
    Analytics.capture(.flightSearchBuilt, builtProperties(source, search))
  }

  static func clicked(_ source: FlightSource, _ link: Loci_Trip_FlightLink, _ search: FlightSearch?) {
    Analytics.capture(.flightLinkClicked, clickedProperties(source, link, search))
  }

  nonisolated static func openedProperties(_ source: FlightSource, destinationIATA: String?) -> [String: Any] {
    var p: [String: Any] = ["source": source.rawValue]
    if let code = FlightSearch.validIATA(destinationIATA) { p["destination_iata"] = code }
    return p
  }

  nonisolated static func builtProperties(_ source: FlightSource, _ search: FlightSearch) -> [String: Any] {
    var p = route(search)
    p["source"] = source.rawValue
    p["has_return"] = search.returnDate != nil
    p["passengers"] = search.passengers
    p["cabin"] = cabinName(search.cabin)
    return p
  }

  nonisolated static func clickedProperties(_ source: FlightSource, _ link: Loci_Trip_FlightLink, _ search: FlightSearch?) -> [String: Any] {
    var p = search.map(route) ?? [:]
    p["source"] = source.rawValue
    p["provider"] = link.provider
    return p
  }

  nonisolated private static func route(_ s: FlightSearch) -> [String: Any] {
    var p: [String: Any] = [:]
    if let o = FlightSearch.validIATA(s.originIATA) { p["origin_iata"] = o }
    if let d = FlightSearch.validIATA(s.destinationIATA) { p["destination_iata"] = d }
    return p
  }

  nonisolated private static func cabinName(_ c: Loci_Trip_FlightCabin) -> String {
    switch c {
    case .economy: "economy"
    case .premiumEconomy: "premium_economy"
    case .business: "business"
    case .first: "first"
    default: "unspecified"
    }
  }
}
