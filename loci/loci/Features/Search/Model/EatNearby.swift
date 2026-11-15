import CoreLocation
import Foundation
import LociConnectProto

/// "Eat nearby": the places to eat Loci has stored around one stop
/// (web: lib/itinerary/eat-nearby.ts). Nothing is generated, and nothing here
/// has been checked against the outside world, which is why the sheet always
/// offers the same search on Google Maps.
nonisolated enum EatNearby {
  static let categories = ["restaurant", "cafe", "bar", "bakery"]
  static let radiusKm = 0.8
  static let maxResults = 8
  /// Under this many, the sheet says how few there are.
  static let few = 3
  /// Metres walked in a minute.
  static let walkingPace = 80.0

  nonisolated struct Option: Equatable, Sendable, Identifiable {
    let place: Loci_Poi_POIDetailedInfo
    let meters: Double
    var id: String { place.stableID }
    var walkMinutes: Int { max(1, Int((meters / EatNearby.walkingPace).rounded())) }
  }

  /// Nearest first, inside the radius, without what the trip already has.
  static func options(
    around anchor: CLLocationCoordinate2D,
    places: [Loci_Poi_POIDetailedInfo],
    onTrip: [Loci_Poi_POIDetailedInfo]
  ) -> [Option] {
    let takenIDs = Set(onTrip.map(\.id).filter { !$0.isEmpty })
    var takenNames = Set(onTrip.map { TripBackedDays.normalized($0.name) })
    let origin = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
    var found: [Option] = []
    for place in places where GoogleMapsRoute.hasCoordinate(place) {
      let name = TripBackedDays.normalized(place.name)
      guard !name.isEmpty, !takenIDs.contains(place.id), !takenNames.contains(name) else { continue }
      let meters = origin.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
      guard meters <= radiusKm * 1000 else { continue }
      takenNames.insert(name)
      found.append(Option(place: place, meters: meters))
    }
    return Array(found.sorted { $0.meters < $1.meters }.prefix(maxResults))
  }

  /// One honest line about what was found.
  static func summary(count: Int, stopName: String) -> String {
    switch count {
    case 0: "Loci doesn't know anywhere to eat within a short walk of \(stopName) yet."
    case 1..<few: "Loci only knows \(count) \(count == 1 ? "place" : "places") to eat near \(stopName)."
    default: "Places Loci knows near \(stopName)"
    }
  }

  static func googleURL(stopName: String, city: String) -> URL? {
    let near = [stopName, city].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ")
    guard !near.isEmpty else { return nil }
    let query = "restaurants near \(near)"
    guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return nil }
    return URL(string: "https://www.google.com/maps/search/?api=1&query=\(encoded)")
  }

  static func isFood(_ category: String) -> Bool {
    let lowered = category.lowercased()
    return !lowered.isEmpty && categories.contains { lowered.contains($0) }
  }
}

/// "Also near this day": a few places a day could take, one tap each
/// (web: lib/itinerary/day-suggestions.ts). No model is asked: the
/// generation's leftovers first, then what Loci has stored around the day.
nonisolated enum DaySuggestions {
  static let extrasRadiusKm = 2.0
  static let nearbyRadiusKm = 1.5
  static let count = 4

  /// The middle of a day's placed stops; nil when none is placed.
  static func centroid(of stops: [Loci_Poi_POIDetailedInfo]) -> CLLocationCoordinate2D? {
    let placed = stops.filter(GoogleMapsRoute.hasCoordinate)
    guard !placed.isEmpty else { return nil }
    return CLLocationCoordinate2D(
      latitude: placed.map(\.latitude).reduce(0, +) / Double(placed.count),
      longitude: placed.map(\.longitude).reduce(0, +) / Double(placed.count)
    )
  }

  /// An extra with a known position has to be near the day; one with none is
  /// kept only when the day has no position either. Nothing already on the
  /// trip, no food (that is "Eat nearby"), no place twice.
  static func pick(
    centroid: CLLocationCoordinate2D?,
    onTrip: [Loci_Poi_POIDetailedInfo],
    extras: [Loci_Poi_POIDetailedInfo],
    nearby: [Loci_Poi_POIDetailedInfo],
    limit: Int = count
  ) -> [Loci_Poi_POIDetailedInfo] {
    var taken = Set(onTrip.map { TripBackedDays.normalized($0.name) })
    let origin = centroid.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }

    func kept(_ places: [Loci_Poi_POIDetailedInfo], within km: Double) -> [(place: Loci_Poi_POIDetailedInfo, meters: Double)] {
      var out: [(place: Loci_Poi_POIDetailedInfo, meters: Double)] = []
      for place in places {
        let name = TripBackedDays.normalized(place.name)
        guard !name.isEmpty, !taken.contains(name), !EatNearby.isFood(place.category) else { continue }
        var meters = Double.greatestFiniteMagnitude
        if let origin {
          guard GoogleMapsRoute.hasCoordinate(place) else { continue }
          meters = origin.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
          guard meters <= km * 1000 else { continue }
        }
        taken.insert(name)
        out.append((place, meters))
      }
      // Stable: equal ratings and distances keep the order they came in.
      return out.enumerated().sorted { a, b in
        if a.element.place.rating != b.element.place.rating { return a.element.place.rating > b.element.place.rating }
        if a.element.meters != b.element.meters { return a.element.meters < b.element.meters }
        return a.offset < b.offset
      }.map(\.element)
    }

    let first = kept(extras, within: extrasRadiusKm)
    let second = kept(nearby, within: nearbyRadiusKm)
    return Array((first + second).map(\.place).prefix(limit))
  }
}
