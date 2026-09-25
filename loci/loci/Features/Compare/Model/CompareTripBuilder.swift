import Foundation
import LociConnectProto

/// The TripDraft Compare's "Save as trip" sends (web: routes/compare/index.tsx
/// save handlers). Pure so the shape is testable without the view.
///
/// `user_id` must be non-empty to pass the proto validator; the handler takes
/// the caller from the token, which is why web sends `"self"` when it has no
/// id at hand. An empty id used to fail every save from this screen.
nonisolated enum CompareTripBuilder {
  /// A day of stops per city: two top places each, one day (single) or two (dual).
  static func weekend(
    column: Loci_Compare_V1_CityCompareColumn,
    dual: Bool,
    columns: [Loci_Compare_V1_CityCompareColumn],
    userID: String?
  ) -> Loci_Trip_TripDraft {
    var trip = Loci_Trip_TripDraft()
    trip.userID = owner(userID)
    trip.cityName = column.cityName
    trip.cityID = column.cityID
    trip.title = dual ? "Weekend: \(columns[0].cityName) + \(columns[1].cityName)" : "\(column.cityName) weekend"
    trip.constraints.pace = .moderate
    let stops = (dual ? Array(columns.prefix(2)) : [column]).flatMap { col in
      col.topPois.prefix(2).enumerated().map { index, poi in
        var stop = Loci_Trip_TripStop()
        stop.poiID = poi.id
        stop.orderIndex = Int32(index)
        stop.name = poi.name
        stop.notes = ""
        return stop
      }
    }
    if dual {
      trip.days = [day(1, Array(stops.prefix(2))), day(2, Array(stops.dropFirst(2).prefix(2)))]
    } else {
      trip.days = [day(1, stops)]
    }
    return trip
  }

  /// One empty day per planned day number, in trip order, plus the plan's legs.
  /// Nil when the plan names no city.
  static func multiCity(plan: Loci_Compare_V1_MultiCityPlan, userID: String?) -> Loci_Trip_TripDraft? {
    guard let first = plan.cities.first else { return nil }
    var trip = Loci_Trip_TripDraft()
    trip.userID = owner(userID)
    trip.cityName = first.cityName
    if first.hasCityID { trip.cityID = first.cityID }
    trip.title = plan.cities.map(\.cityName).joined(separator: " + ")
    trip.constraints.pace = .moderate
    trip.days = plan.cities.flatMap { city in
      city.dayNumbers.map { number in
        var day = day(Int(number), [])
        day.cityName = city.cityName
        if city.hasCityID { day.cityID = city.cityID }
        day.cityLat = city.lat
        day.cityLon = city.lon
        return day
      }
    }.sorted { $0.dayNumber < $1.dayNumber }
    trip.legs = plan.legs
    return trip
  }

  private static func owner(_ userID: String?) -> String {
    (userID?.isEmpty == false ? userID : nil) ?? "self"
  }

  private static func day(_ number: Int, _ stops: [Loci_Trip_TripStop]) -> Loci_Trip_TripDay {
    var day = Loci_Trip_TripDay()
    day.dayNumber = Int32(number)
    day.stops = stops
    return day
  }
}
