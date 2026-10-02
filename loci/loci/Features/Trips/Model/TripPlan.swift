import Foundation
import LociConnectProto

/// The rules behind the trip page's Plan section (web: lib/api/trip-plan.ts):
/// which cities a stay is for, where a city is, and hotels by stars.
nonisolated enum TripPlan {
  /// The cities a stay can be set for: a multi-city trip's, else the trip's own.
  static func cities(of trip: Loci_Trip_TripDraft) -> [String] {
    if !trip.cities.isEmpty { return trip.cities.map(\.cityName) }
    return trip.cityName.isEmpty ? [] : [trip.cityName]
  }

  /// Where a city of the trip is: the first day spent there that has a position.
  /// A day with no city name is the trip's own city.
  static func coordinate(of city: String, in trip: Loci_Trip_TripDraft) -> (latitude: Double, longitude: Double)? {
    let want = city.trimmingCharacters(in: .whitespaces).lowercased()
    let isPrimary = trip.cityName.trimmingCharacters(in: .whitespaces).lowercased() == want
    for day in trip.days {
      let name = day.cityName.trimmingCharacters(in: .whitespaces).lowercased()
      guard name == want || (name.isEmpty && isPrimary) else { continue }
      guard day.hasCityLat, day.hasCityLon else { continue }
      return (day.cityLat, day.cityLon)
    }
    return nil
  }

  /// A hotel's stars as a number: "4", "4.5", "4★", "★★★★". A number wins.
  static func stars(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    let digits = trimmed.prefix { $0.isNumber || $0 == "." }
    if !digits.isEmpty, let value = Double(digits) { return (value > 0 && value <= 5) ? value : nil }
    let glyphs = trimmed.filter { $0 == "★" }.count
    return (1...5).contains(glyphs) ? Double(glyphs) : nil
  }

  /// Hotels whose whole stars equal `stars`, best rated first. 0 is any rating
  /// and keeps unrated hotels; a chosen rating drops them.
  static func hotels(_ hotels: [Loci_Favorites_V1_HotelDetails], stars want: Int) -> [Loci_Favorites_V1_HotelDetails] {
    hotels
      .filter { hotel in
        guard want > 0 else { return true }
        guard let value = stars(hotel.starRating) else { return false }
        return Int(value.rounded(.down)) == want
      }
      .sorted { $0.rating > $1.rating }
  }

  /// The trip's dates, when both are set.
  @MainActor static func dates(of trip: Loci_Trip_TripDraft) -> (start: Date, end: Date)? {
    guard trip.hasStartDate, trip.hasEndDate,
      let start = CalendarMath.parseDateKey(trip.startDate),
      let end = CalendarMath.parseDateKey(trip.endDate)
    else { return nil }
    return (start, end)
  }

  /// A new flight search departs on the trip's first day, else today.
  @MainActor static func defaultDeparture(of trip: Loci_Trip_TripDraft, today: Date) -> String {
    trip.hasStartDate && !trip.startDate.isEmpty ? trip.startDate : CalendarMath.dateKey(today)
  }

  /// The stay set for a city, matched loosely.
  static func stay(for city: String, in trip: Loci_Trip_TripDraft) -> Loci_Trip_TripStay? {
    trip.stays.first { $0.cityName.caseInsensitiveCompare(city) == .orderedSame }
  }
}
