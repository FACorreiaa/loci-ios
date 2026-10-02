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
}

/// One flight search from the Plan section's form.
nonisolated struct FlightSearch: Equatable, Sendable {
  var origin = ""
  var destination = ""
  var departDate = ""      // YYYY-MM-DD
  var returnDate: String?  // YYYY-MM-DD
  var passengers = 1
  var cabin: Loci_Trip_FlightCabin = .unspecified

  var originPlace: Loci_Trip_FlightPlace { var p = Loci_Trip_FlightPlace(); p.name = origin.trimmingCharacters(in: .whitespaces); return p }
  var destinationPlace: Loci_Trip_FlightPlace { var p = Loci_Trip_FlightPlace(); p.name = destination.trimmingCharacters(in: .whitespaces); return p }
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
