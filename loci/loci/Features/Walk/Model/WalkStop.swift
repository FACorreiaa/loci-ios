import CoreLocation
import Foundation
import LociConnectProto

/// One place on a day being walked: a name, where it is, and the POI the
/// directions are fetched for. Only stops with a usable coordinate become one.
nonisolated struct WalkStop: Identifiable, Hashable {
  let id: String
  let name: String
  let poi: Loci_Poi_POIDetailedInfo
  let coordinate: CLLocationCoordinate2D

  static func == (a: WalkStop, b: WalkStop) -> Bool { a.id == b.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A day of stops to walk in order, from a trip day or a saved itinerary's day.
/// `withoutLocation` counts the stops left out because they have no coordinate.
nonisolated struct WalkDay: Identifiable, Hashable {
  let id: String
  let title: String
  let stops: [WalkStop]
  let withoutLocation: Int

  static func from(trip: Loci_Trip_TripDraft, day: Loci_Trip_TripDay) -> WalkDay {
    var stops: [WalkStop] = []
    for stop in day.stops {
      guard let coordinate = DayTimeline.coordinate(of: stop) else { continue }
      stops.append(WalkStop(id: stop.id, name: stop.name.isEmpty ? stop.poi.name : stop.name, poi: stop.poi, coordinate: coordinate))
    }
    let city = day.cityName.isEmpty || day.cityName == trip.cityName ? "" : " · \(day.cityName)"
    return WalkDay(
      id: "trip:\(trip.id):\(day.id)",
      title: "Day \(day.dayNumber)\(city)",
      stops: stops,
      withoutLocation: day.stops.count - stops.count
    )
  }

  static func from(group: DayGroup, sessionId: String, cityName: String) -> WalkDay {
    let usable = group.stops.filter(GoogleMapsRoute.hasCoordinate)
    let stops = usable.map {
      WalkStop(id: $0.stableID, name: $0.name, poi: $0, coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
    }
    return WalkDay(
      id: "session:\(sessionId):\(group.number)",
      title: cityName.isEmpty ? "Day \(group.number)" : "Day \(group.number) · \(cityName)",
      stops: stops,
      withoutLocation: group.stops.count - stops.count
    )
  }
}
