import Foundation
import LociConnectProto

/// Where a card on a result page sits in the trip behind it.
nonisolated struct TripStopRef: Equatable, Sendable {
  let stopID: String
  let dayID: String
  /// Position within its day, and how many stops that day has.
  let index: Int
  let count: Int
}

/// One day of the trip, as the page labels it.
nonisolated struct TripDayRef: Equatable, Sendable, Identifiable {
  let id: String
  /// 1-based position on the page.
  let number: Int
}

/// A result page drawn from the trip the server saved for it, instead of from
/// the generation (web: lib/itinerary/trip-view.ts mergeTripIntoStops). The
/// trip decides which stops there are and in what order; the generated place
/// supplies the photo, rating and description when one matches.
nonisolated struct TripBackedDays: Equatable, Sendable {
  let groups: [DayGroup]
  let days: [TripDayRef]
  /// Keyed by the card's `stableID`.
  let refs: [String: TripStopRef]
  /// Generated places that are not on the trip: "More to explore".
  let extras: [Loci_Poi_POIDetailedInfo]

  /// Case, accents and punctuation do not make two names different places.
  static func normalized(_ name: String) -> String {
    name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  static func build(trip: Loci_Trip_TripDraft, generated: [Loci_Poi_POIDetailedInfo]) -> TripBackedDays {
    var byID: [String: Int] = [:]
    var byName: [String: Int] = [:]
    for (offset, place) in generated.enumerated() {
      if !place.id.isEmpty, byID[place.id] == nil { byID[place.id] = offset }
      let name = normalized(place.name)
      if !name.isEmpty, byName[name] == nil { byName[name] = offset }
    }
    var used: Set<Int> = []
    var keys: Set<String> = []
    var groups: [DayGroup] = []
    var days: [TripDayRef] = []
    var refs: [String: TripStopRef] = [:]

    let ordered = trip.days.sorted { $0.dayNumber < $1.dayNumber }
    for (dayOffset, day) in ordered.enumerated() {
      let stops = day.stops.sorted { $0.orderIndex < $1.orderIndex }
      var cards: [Loci_Poi_POIDetailedInfo] = []
      for (index, stop) in stops.enumerated() {
        // Each generated card is used once: a place on the trip twice gets the
        // rich card the first time and a plain one after.
        let match = [stop.poiID.isEmpty ? nil : byID[stop.poiID], byName[normalized(stop.name)]]
          .compactMap { $0 }
          .first { !used.contains($0) }
        var card = match.map { generated[$0] } ?? plainCard(for: stop)
        if let match { used.insert(match) }
        fillPin(&card, from: stop)
        if keys.contains(card.stableID) { card.id = "trip-stop-\(stop.id)" }
        keys.insert(card.stableID)
        refs[card.stableID] = TripStopRef(stopID: stop.id, dayID: day.id, index: index, count: stops.count)
        cards.append(card)
      }
      days.append(TripDayRef(id: day.id, number: dayOffset + 1))
      groups.append(DayGroup(number: dayOffset + 1, stops: cards))
    }
    let extras = generated.enumerated().filter { !used.contains($0.offset) }.map(\.element)
      .filter { !keys.contains($0.stableID) }
    return TripBackedDays(groups: groups, days: days, refs: refs, extras: extras)
  }

  /// A stop the generation knows nothing about: added by hand, from a link, or
  /// on another device. The server's own copy of the place when it sent one.
  private static func plainCard(for stop: Loci_Trip_TripStop) -> Loci_Poi_POIDetailedInfo {
    var card = stop.hasPoi ? stop.poi : Loci_Poi_POIDetailedInfo()
    if card.id.isEmpty { card.id = stop.poiID.isEmpty ? "trip-stop-\(stop.id)" : stop.poiID }
    card.name = stop.name
    return card
  }

  /// The stop's own pin, for a card that has none.
  private static func fillPin(_ card: inout Loci_Poi_POIDetailedInfo, from stop: Loci_Trip_TripStop) {
    if !GoogleMapsRoute.hasCoordinate(card), stop.hasLatitude, stop.hasLongitude, stop.latitude != 0 || stop.longitude != 0 {
      card.latitude = stop.latitude
      card.longitude = stop.longitude
    }
    if card.address.isEmpty, stop.hasAddress, !stop.address.isEmpty { card.address = stop.address }
  }
}

nonisolated extension GoogleMapsRoute {
  /// The place's own page on Google Maps, found by name and city: where its
  /// reviews, photos and opening hours are (web: lib/trip-kit.ts
  /// buildGooglePlaceUrl). By name on purpose; a coordinate opens a bare pin.
  static func placeURL(name: String, city: String) -> URL? {
    let parts = [name, city].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard let first = parts.first, first == name.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
    let query = parts.joined(separator: ", ")
    guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return nil }
    return URL(string: "https://www.google.com/maps/search/?api=1&query=\(encoded)")
  }
}
