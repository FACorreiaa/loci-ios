import Foundation
import LociConnectProto

/// Where a hotel report was drawn.
nonisolated enum HotelCompareSurface: String, Sendable {
  /// The Assistant tab's result page.
  case chat
  /// The hold-to-ask overlay.
  case overlay
  /// The trip page's "Ask the planner" sheet.
  case planner
}

/// How "Add … to trip" reached the trip.
nonisolated enum HotelCompareVia: String, Sendable {
  /// The proposal the server sent with the report.
  case proposal
  /// The traveller chose the trip.
  case picker
}

/// Hotel comparison and stay transport usage. Counts and booleans only: no
/// message text, no link, no hotel, stop or city name leaves the device.
enum HotelCompareAnalytics {
  static func reportShown(_ surface: HotelCompareSurface, _ report: Loci_Chat_HotelComparisonReport, hasProposal: Bool) {
    Analytics.capture(.hotelReportShown, reportShownProperties(surface, report, hasProposal: hasProposal))
  }

  static func addTapped(_ surface: HotelCompareSurface, via: HotelCompareVia, option: Int, recommended: Bool) {
    Analytics.capture(.hotelReportAddTapped, addTappedProperties(surface, via: via, option: option, recommended: recommended))
  }

  static func staySet(_ surface: HotelCompareSurface, via: HotelCompareVia, hotel: Loci_Chat_ComparedHotel?) {
    Analytics.capture(.staySetFromReport, staySetProperties(surface, via: via, hotel: hotel))
  }

  static func transportViewed(_ transport: Loci_Trip_StayTransport) {
    Analytics.capture(.stayTransportViewed, transportViewedProperties(transport))
  }

  static func directionsOpened(target: String, provider: String, source: String, suggestedMode: String? = nil) {
    Analytics.capture(.stayDirectionsOpened, directionsProperties(target: target, provider: provider, source: source, suggestedMode: suggestedMode))
  }

  nonisolated static func reportShownProperties(
    _ surface: HotelCompareSurface,
    _ report: Loci_Chat_HotelComparisonReport,
    hasProposal: Bool
  ) -> [String: Any] {
    [
      "surface": surface.rawValue,
      "hotels": report.hotels.count,
      "identified": report.hotels.count(where: \.identified),
      "has_verdict": !report.verdict.isEmpty,
      "has_recommendation": HotelReport.recommendedIndex(report) != nil,
      "web_search_used": report.webSearchUsed,
      "sources": report.sources.count,
      "has_trip": hasProposal,
    ]
  }

  nonisolated static func addTappedProperties(_ surface: HotelCompareSurface, via: HotelCompareVia, option: Int, recommended: Bool) -> [String: Any] {
    ["surface": surface.rawValue, "via": via.rawValue, "option": option, "recommended": recommended]
  }

  nonisolated static func staySetProperties(_ surface: HotelCompareSurface, via: HotelCompareVia, hotel: Loci_Chat_ComparedHotel?) -> [String: Any] {
    var p: [String: Any] = ["surface": surface.rawValue, "via": via.rawValue]
    if let hotel {
      p["identified"] = hotel.identified
      p["has_coordinates"] = hotel.stay.hasLatitude && hotel.stay.hasLongitude
    }
    return p
  }

  nonisolated static func transportViewedProperties(_ transport: Loci_Trip_StayTransport) -> [String: Any] {
    [
      "status": statusName(transport.status),
      "stops": transport.stops.count,
      "routed_stops": transport.stops.count(where: \.routed),
      "day_starts": transport.dayStarts.count,
      "has_airport": transport.hasAirport,
    ]
  }

  nonisolated static func directionsProperties(target: String, provider: String, source: String, suggestedMode: String?) -> [String: Any] {
    var p: [String: Any] = ["target": target, "provider": provider, "source": source]
    // Only the two values the server defines; anything else is not passed on.
    if let mode = suggestedMode, mode == "walk" || mode == "transit" { p["suggested_mode"] = mode }
    return p
  }

  nonisolated private static func statusName(_ status: Loci_Trip_StayTransportStatus) -> String {
    switch status {
    case .ready: "ready"
    case .noCoordinates: "no_coordinates"
    case .unavailable: "unavailable"
    default: "unspecified"
    }
  }
}
