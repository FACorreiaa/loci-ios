import Foundation
import LociConnectProto
import SwiftProtobuf

/// The requests Add to trip sends and the words it shows, kept pure so each
/// can be tested (web: lib/api/trips.ts useTrips / useAddStop / useSaveTrip).
nonisolated enum AddToTripPayload {
  /// web: useTrips → ListTrips{page 1, pageSize 50}, the same page TripsView asks for.
  static func listTrips() -> Loci_Trip_ListTripsRequest {
    var request = Loci_Trip_ListTripsRequest()
    request.pagination.page = 1
    request.pagination.pageSize = 50
    return request
  }

  static func getTrip(id: String) -> Loci_Trip_GetTripRequest {
    var request = Loci_Trip_GetTripRequest()
    request.tripID = id
    return request
  }

  /// AddStop against a trip just read from GetTrip, so `baseVersion` is the
  /// server's current one. Web sends the version from its cached list, which
  /// no stop mutation refreshes: its second add in a row is refused.
  ///
  /// The day is named by its number and resolved to an id here, in the fresh
  /// trip: every save rewrites `trip_days`, so a day's id changes with each
  /// edit and an id picked from an older copy would no longer be found. Nil
  /// when the trip has no such day any more.
  static func addStop(
    to trip: Loci_Trip_TripDraft,
    dayNumber: Int32,
    poi: Loci_Poi_POIDetailedInfo,
    stopID: String = UUID().uuidString.lowercased()
  ) -> Loci_Trip_AddStopRequest? {
    guard let day = trip.days.first(where: { $0.dayNumber == dayNumber }), !day.id.isEmpty else { return nil }
    var request = Loci_Trip_AddStopRequest()
    request.tripID = trip.id
    request.dayID = day.id
    request.baseVersion = trip.version
    request.stop = TripStopBuilder.stop(from: poi, orderIndex: day.stops.count, id: stopID)
    return request
  }

  /// "Create a trip" with nothing to pick from: SaveTrip{baseVersion 0} with
  /// the place's city and one day that already holds the place (Compare's
  /// path). `user_id` must be non-empty to pass validation; the handler takes
  /// the caller from the token, which is why web sends `"self"`.
  static func newTrip(for poi: Loci_Poi_POIDetailedInfo, cityName: String, userID: String?) -> Loci_Trip_SaveTripRequest {
    let city = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
    var trip = Loci_Trip_TripDraft()
    trip.userID = (userID?.isEmpty == false ? userID : nil) ?? "self"
    trip.cityName = city
    if SavedPlace.isStoredID(poi.cityID) { trip.cityID = poi.cityID }
    trip.title = city.isEmpty ? "My trip" : "\(city) trip"
    trip.constraints.pace = .moderate
    var day = Loci_Trip_TripDay()
    day.dayNumber = 1
    day.cityName = city
    day.stops = [TripStopBuilder.stop(from: poi, orderIndex: 0)]
    trip.days = [day]
    var request = Loci_Trip_SaveTripRequest()
    request.trip = trip
    request.baseVersion = 0
    return request
  }

  // MARK: - Words

  static func tripTitle(_ trip: Loci_Trip_TripDraft) -> String {
    if !trip.title.isEmpty { return trip.title }
    return trip.cityName.isEmpty ? "Untitled trip" : trip.cityName
  }

  /// "Day 2 · Tue 3 Oct · Porto": the date when the day has one (stored as
  /// UTC midnight, so read in UTC), the city when it isn't the trip's own.
  static func dayLabel(_ day: Loci_Trip_TripDay, tripCity: String = "", locale: Locale = .current) -> String {
    var parts = ["Day \(day.dayNumber)"]
    if day.hasDate { parts.append(dayDate(day.date.date, locale: locale)) }
    if !day.cityName.isEmpty, day.cityName.caseInsensitiveCompare(tripCity) != .orderedSame { parts.append(day.cityName) }
    return parts.joined(separator: " · ")
  }

  static func stopCount(_ day: Loci_Trip_TripDay) -> String {
    day.stops.count == 1 ? "1 stop" : "\(day.stops.count) stops"
  }

  static func addedMessage(dayNumber: Int32) -> String { "Added to Day \(dayNumber)" }

  private static func dayDate(_ date: Date, locale: Locale) -> String {
    var style = Date.FormatStyle(date: .omitted, time: .omitted).weekday(.abbreviated).day().month(.abbreviated)
    style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    style.locale = locale
    return date.formatted(style)
  }
}
