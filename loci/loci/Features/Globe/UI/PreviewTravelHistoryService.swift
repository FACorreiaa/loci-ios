import Foundation

/// Offline sample data for `-designPreview globe` and `globeEmpty`: a year of
/// Iberian trips, a flight to Tokyo and one across the Pacific (so the
/// antimeridian split is on screen), or nothing at all.
nonisolated struct PreviewTravelHistoryService: TravelHistoryService {
  var data: GlobeData = .preview

  func globeData() async throws -> GlobeData { data }
}

nonisolated extension GlobeData {
  static var previewEmpty: GlobeData { GlobeData(cities: [], legs: [], summary: TravelSummary(), backfilled: true) }

  static var preview: GlobeData {
    let now = Date()
    func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
    func city(_ id: String, _ name: String, _ country: String, _ lat: Double, _ lon: Double, _ visits: Int, _ last: Double) -> GlobeCity {
      GlobeCity(
        id: id,
        cityName: name,
        country: country,
        point: GeoPoint(latitude: lat, longitude: lon),
        visitCount: visits,
        firstVisitAt: daysAgo(last + 200),
        lastVisitAt: daysAgo(last)
      )
    }
    let cities = [
      city("lis", "Lisbon", "Portugal", 38.7223, -9.1393, 6, 12), city("opo", "Porto", "Portugal", 41.1579, -8.6291, 3, 40),
      city("mad", "Madrid", "Spain", 40.4168, -3.7038, 2, 70), city("bcn", "Barcelona", "Spain", 41.3874, 2.1686, 1, 95),
      city("tyo", "Tokyo", "Japan", 35.6762, 139.6503, 1, 150), city("akl", "Auckland", "New Zealand", -36.8485, 174.7633, 1, 300),
      city("scl", "Santiago", "Chile", -33.4489, -70.6693, 1, 290),
    ]
    var keys = GlobeLegKey()
    func leg(_ from: GlobeCity, _ to: GlobeCity, _ mode: String, _ days: Double) -> GlobeLeg {
      let when = daysAgo(days)
      return GlobeLeg(
        id: keys.next(tripId: "trip-\(Int(days))", from: from.cityName, to: to.cityName, occurredAt: when),
        fromName: from.cityName,
        toName: to.cityName,
        from: from.point,
        to: to.point,
        distanceKm: GreatCircle.distanceKm(from.point, to.point),
        tripId: "trip-\(Int(days))",
        mode: mode,
        occurredAt: when
      )
    }
    let legs = [
      leg(cities[0], cities[1], "rail", 40), leg(cities[1], cities[2], "fly", 70), leg(cities[2], cities[3], "rail", 95),
      leg(cities[0], cities[4], "fly", 150), leg(cities[5], cities[6], "fly", 290),
    ]
    return GlobeData(
      cities: cities,
      legs: legs,
      summary: TravelSummary(
        citiesVisited: 7,
        countriesVisited: 5,
        poisVisited: 48,
        distanceKm: legs.reduce(0) { $0 + $1.distanceKm },
        tripsCompleted: 5,
        citiesVisitedPrev: 5,
        countriesVisitedPrev: 4,
        poisVisitedPrev: 40,
        periodDays: 365
      ),
      backfilled: true
    )
  }
}
