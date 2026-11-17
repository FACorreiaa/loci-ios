import Foundation
import LociConnectProto

/// The words of "Getting around from <stay>" on a trip (web:
/// components/trip/StayTransportSection.tsx). Pure, so each line and each
/// status can be tested. Stops are what OpenStreetMap has mapped near the
/// stay; nothing here claims a timetable.
nonisolated enum StayTransportFormat {
  /// One stop: its kind in the leading column, then the line about it.
  struct StopRow: Equatable, Sendable, Identifiable {
    let id: Int
    let mode: String
    let symbol: String
    let line: String
    let spoken: String
  }

  /// A maps app that can open a journey.
  struct Directions: Equatable, Sendable, Identifiable {
    enum Provider: String, Sendable { case apple, google }

    let provider: Provider
    let url: URL

    var id: String { provider.rawValue }
    var label: String {
      switch provider {
      case .apple: String(localized: "Apple Maps")
      case .google: String(localized: "Google Maps")
      }
    }
  }

  static func title(_ transport: Loci_Trip_StayTransport, stayName: String) -> String {
    let name = transport.stayName.isEmpty ? stayName : transport.stayName
    return name.isEmpty ? String(localized: "Getting around from your stay") : String(localized: "Getting around from \(name)")
  }

  static func stopRows(_ transport: Loci_Trip_StayTransport) -> [StopRow] {
    transport.stops.enumerated().map { offset, stop in
      let mode = TransitFormat.modeLabel(stop.mode)
      return StopRow(
        id: offset,
        mode: mode,
        symbol: TransitFormat.modeSymbol(stop.mode),
        line: TransitFormat.stopLine(stop),
        spoken: "\(mode): \(TransitFormat.spokenStopLine(stop))"
      )
    }
  }

  /// "BCN · 14 km", or the airport's name when it has no code.
  static func airportLine(_ airport: Loci_Trip_AirportConnection) -> String {
    let code = airport.iata.trimmingCharacters(in: .whitespaces)
    let name = airport.airportName.trimmingCharacters(in: .whitespaces)
    var parts = [code.isEmpty ? name : code].filter { !$0.isEmpty }
    if airport.distanceKm > 0 {
      parts.append(String(localized: "\(airport.distanceKm.formatted(.number.precision(.fractionLength(airport.distanceKm < 10 ? 1 : 0)))) km"))
    }
    return parts.joined(separator: " · ")
  }

  /// What to say instead of, or above, the stops. Nil when there are stops
  /// and nothing went wrong.
  static func statusMessage(_ transport: Loci_Trip_StayTransport) -> String? {
    switch transport.status {
    case .noCoordinates:
      return String(localized: "We don't know where this stay is, so there's nothing to measure from.")
    case .unavailable:
      return String(localized: "The map data couldn't be reached, so nearby stops aren't shown right now.")
    default:
      return transport.stops.isEmpty ? String(localized: "No public transport stops are mapped within a short walk of this stay.") : nil
    }
  }

  /// The credit for the map data, then the limit of what it knows.
  static func footnote(_ transport: Loci_Trip_StayTransport) -> String {
    let honest = String(localized: "No live timetables: check times before you travel.")
    var credit = transport.attribution.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !credit.isEmpty else { return honest }
    if let last = credit.last, !".!?".contains(last) { credit += "." }
    return "\(credit) \(honest)"
  }

  /// The links that open a journey: Apple's first, each only when it is https.
  static func directions(apple: String, google: String) -> [Directions] {
    var links: [Directions] = []
    if let url = TransitFormat.httpsURL(apple) { links.append(Directions(provider: .apple, url: url)) }
    if let url = TransitFormat.httpsURL(google) { links.append(Directions(provider: .google, url: url)) }
    return links
  }

  static func isTransitSuggested(_ start: Loci_Trip_DayStart) -> Bool { start.suggestedMode == "transit" }

  /// "From your hotel: 12 min walk", or "From your hotel: public transport
  /// suggested" when the first stop is too far to walk. Nil when the server
  /// measured nothing.
  static func dayStartLine(_ start: Loci_Trip_DayStart) -> String? {
    if isTransitSuggested(start) {
      let far = start.distanceM > 0 ? " (\(TransitFormat.distance(start.distanceM)))" : ""
      return String(localized: "From your hotel: public transport suggested\(far)")
    }
    guard let walk = TransitFormat.walk(minutes: start.walkMinutes, metres: start.distanceM) else { return nil }
    return String(localized: "From your hotel: \(walk)")
  }

  /// A walk that is a straight-line estimate says so, in the words the
  /// walking legs between stops use.
  static func isUnchecked(_ start: Loci_Trip_DayStart) -> Bool { !isTransitSuggested(start) && !start.routed }

  /// The same line for VoiceOver, naming where the day begins.
  static func spokenDayStart(_ start: Loci_Trip_DayStart) -> String? {
    guard var line = dayStartLine(start) else { return nil }
    let stop = start.firstStopName.trimmingCharacters(in: .whitespaces)
    if !stop.isEmpty { line += String(localized: ", to \(stop)") }
    if isUnchecked(start) { line += ". " + String(localized: "Straight-line estimate, route not checked") }
    return line
  }

  /// The day's start, by the day's id, else by its number: the server gives
  /// every day a new id on each save, so an older answer may only match by number.
  static func dayStart(in transports: [Loci_Trip_StayTransport], dayID: String, dayNumber: Int32) -> Loci_Trip_DayStart? {
    let starts = transports.flatMap(\.dayStarts)
    if !dayID.isEmpty, let match = starts.first(where: { $0.dayID == dayID }) { return match }
    return starts.first { $0.dayNumber == dayNumber && dayNumber > 0 }
  }
}
