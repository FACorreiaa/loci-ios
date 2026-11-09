import Foundation
import LociConnectProto

/// The Plan section's reads: hotels near a city, and the flight search links
/// the server builds. Writes go through TripEditorView.apply.
nonisolated enum TripPlanAPI {
  static func hotelsNear(latitude: Double, longitude: Double) async throws -> [Loci_Favorites_V1_HotelDetails] {
    var request = Loci_Favorites_V1_GetNearbyHotelsRequest()
    request.latitude = latitude
    request.longitude = longitude
    request.radiusKm = 5
    request.limit = 40
    return try await rpc("Could not look up hotels.", request) { await ResultsAPI.favorites.getNearbyHotels(request: $0, headers: [:]) }.hotels
  }

  static func flightLinks(_ search: FlightSearch) async throws(TripRPCError) -> [Loci_Trip_FlightLink] {
    var request = Loci_Trip_BuildFlightLinksRequest()
    request.origin = search.originPlace
    request.destination = search.destinationPlace
    request.departDate = search.departDate
    if let ret = search.returnDate { request.returnDate = ret }
    request.passengers = Int32(search.passengers)
    request.cabin = search.cabin
    return try await TripAPI.call("Could not build the flight search.", request) {
      await TripAPI.client.buildFlightLinks(request: $0, headers: [:])
    }.links
  }

  /// Airport autocomplete; empty under two characters.
  static func searchAirports(_ query: String) async throws(TripRPCError) -> [Loci_Trip_FlightPlaceOption] {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard q.count >= 2 else { return [] }
    var request = Loci_Trip_SearchAirportsRequest()
    request.query = q
    return try await TripAPI.call("Could not search airports.", request) {
      await TripAPI.client.searchAirports(request: $0, headers: [:])
    }.options
  }

  /// The airport (or metro code) a city's flight search lands at, if any.
  static func resolveDestination(city: String, countryCode: String? = nil, latitude: Double? = nil, longitude: Double? = nil)
    async throws(TripRPCError) -> Loci_Trip_FlightPlaceOption?
  {
    var request = Loci_Trip_ResolveFlightDestinationRequest()
    request.city = city
    if let cc = countryCode, cc.count == 2 { request.countryCode = cc }
    if let latitude { request.latitude = latitude }
    if let longitude { request.longitude = longitude }
    let response = try await TripAPI.call("Could not find the airport.", request) {
      await TripAPI.client.resolveFlightDestination(request: $0, headers: [:])
    }
    return response.hasDestination ? response.destination : nil
  }
}

/// One flight search from the Plan section's form.
nonisolated struct FlightSearch: Equatable, Sendable {
  var origin = ""
  var destination = ""
  var departDate = ""      // YYYY-MM-DD
  var returnDate: String?  // YYYY-MM-DD
  var passengers = 1
  var cabin: Loci_Trip_FlightCabin = .unspecified
  /// Set when the traveller picked an airport from the suggestions; typed
  /// text has none, and the server then builds Google Flights only.
  var originIATA: String?
  var destinationIATA: String?

  var originPlace: Loci_Trip_FlightPlace { Self.place(origin, originIATA) }
  var destinationPlace: Loci_Trip_FlightPlace { Self.place(destination, destinationIATA) }

  /// The code as the server's validator takes it (^[A-Z]{3}$), or nil.
  static func validIATA(_ code: String?) -> String? {
    guard let c = code?.trimmingCharacters(in: .whitespaces).uppercased(), c.count == 3,
      c.allSatisfy({ $0.isASCII && $0.isUppercase })
    else { return nil }
    return c
  }

  private static func place(_ name: String, _ iata: String?) -> Loci_Trip_FlightPlace {
    var p = Loci_Trip_FlightPlace()
    p.name = name.trimmingCharacters(in: .whitespaces)
    if let code = validIATA(iata) { p.iata = code }
    return p
  }

  var isReady: Bool {
    !origin.trimmingCharacters(in: .whitespaces).isEmpty && !destination.trimmingCharacters(in: .whitespaces).isEmpty
      && !departDate.isEmpty && (returnDate.map { $0 >= departDate } ?? true)
  }

  /// The flight AddFlight saves (the server builds its links again).
  var flight: Loci_Trip_TripFlight {
    var f = Loci_Trip_TripFlight()
    f.origin = originPlace
    f.destination = destinationPlace
    f.departDate = departDate
    if let returnDate { f.returnDate = returnDate }
    f.passengers = Int32(passengers)
    f.cabin = cabin
    return f
  }
}

extension FlightSearch {
  /// The search a saved flight stands for (analytics on its links).
  init(_ f: Loci_Trip_TripFlight) {
    self.init(
      origin: f.origin.name,
      destination: f.destination.name,
      departDate: f.departDate,
      returnDate: f.hasReturnDate ? f.returnDate : nil,
      passengers: Int(f.passengers),
      cabin: f.cabin,
      originIATA: f.origin.hasIata ? f.origin.iata : nil,
      destinationIATA: f.destination.hasIata ? f.destination.iata : nil
    )
  }
}
