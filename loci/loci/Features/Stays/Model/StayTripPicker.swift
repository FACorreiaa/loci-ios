import Connect
import Foundation
import LociConnectProto

/// One of the traveller's trips, as the "which trip?" sheet lists it for a
/// hotel from a comparison report.
nonisolated struct StayTripOption: Equatable, Sendable, Identifiable {
  let trip: Loci_Trip_TripDraft
  /// The trip has the hotel's city, so it can take the stay.
  let isEligible: Bool

  var id: String { trip.id }
}

/// The rules for putting a compared hotel on a trip when the server sent no
/// proposal (web: components/chat/HotelTripPicker.tsx): a stay belongs to one
/// of the trip's cities, and only the trip's owner sets it.
nonisolated enum StayTripPicker {
  /// The trip's own spelling of `city`, or nil when the trip does not go there.
  /// Case, accents and punctuation do not make two names different cities.
  static func matchingCity(in trip: Loci_Trip_TripDraft, city: String) -> String? {
    let want = TripBackedDays.normalized(city)
    guard !want.isEmpty else { return nil }
    return TripPlan.cities(of: trip).first { TripBackedDays.normalized($0) == want }
  }

  /// The caller's own trips, those with the city first; each group keeps the
  /// server's order. A trip someone else owns is left out: it cannot take a stay.
  static func options(_ trips: [Loci_Trip_TripDraft], city: String) -> [StayTripOption] {
    let own = trips.filter { !$0.hasOwner }.map { StayTripOption(trip: $0, isEligible: matchingCity(in: $0, city: city) != nil) }
    return own.filter(\.isEligible) + own.filter { !$0.isEligible }
  }

  /// Why a trip is greyed out.
  static func reason(city: String) -> String { String(localized: "\(city) isn't on this trip") }

  /// What the planner is asked when no trip has the city.
  static func planPrompt(city: String) -> String { String(localized: "Plan a trip to \(city)") }

  /// SetStay against a trip just read, so `baseVersion` is the server's
  /// current one. The stay takes the trip's spelling of the city. Nil when the
  /// trip no longer has the city, or is not the caller's to change.
  static func setStay(_ stay: Loci_Trip_TripStay, on trip: Loci_Trip_TripDraft) -> Loci_Trip_SetStayRequest? {
    guard !trip.hasOwner, let city = matchingCity(in: trip, city: stay.cityName) else { return nil }
    var request = Loci_Trip_SetStayRequest()
    request.tripID = trip.id
    request.stay = stay
    request.stay.cityName = city
    request.baseVersion = trip.version
    return request
  }
}

nonisolated enum AddStayError: Error, Equatable, LocalizedError {
  /// The city left the trip (or the trip changed hands) since the list was read.
  case cityMissing(String)

  var errorDescription: String? {
    switch self {
    case .cityMissing(let city): String(localized: "\(city) is no longer on that trip. Pick another one.")
    }
  }
}

/// What the picker needs from TripService, behind a protocol so the tests and
/// the design preview run without a session.
nonisolated protocol StayService: Sendable {
  /// The caller's own trips (ListTrips without members' trips).
  func trips() async throws -> [Loci_Trip_TripDraft]
  func trip(id: String) async throws -> Loci_Trip_TripDraft
  /// Throws `AddToTripError.staleVersion` for a refused `baseVersion`.
  func setStay(_ request: Loci_Trip_SetStayRequest) async throws -> Loci_Trip_TripDraft
}

nonisolated struct ConnectStayService: StayService {
  func trips() async throws -> [Loci_Trip_TripDraft] { try await AddToTripAPI.trips() }
  func trip(id: String) async throws -> Loci_Trip_TripDraft { try await AddToTripAPI.trip(id: id) }

  func setStay(_ request: Loci_Trip_SetStayRequest) async throws -> Loci_Trip_TripDraft {
    let response = await withAuthRetry { await TripAPI.client.setStay(request: request, headers: [:]) }
    if response.error?.code == .failedPrecondition { throw AddToTripError.staleVersion }
    return try response.unwrap("Could not save the hotel.")
  }
}

nonisolated enum AddStayFlow {
  /// Read the trip for a fresh version, set the stay, and on a stale version
  /// read and set once more (the same shape as `AddToTripFlow.add`).
  static func set(_ stay: Loci_Trip_TripStay, tripID: String, service: some StayService) async throws -> Loci_Trip_TripDraft {
    do {
      return try await attempt(stay, tripID: tripID, service: service)
    } catch AddToTripError.staleVersion {
      return try await attempt(stay, tripID: tripID, service: service)
    }
  }

  private static func attempt(_ stay: Loci_Trip_TripStay, tripID: String, service: some StayService) async throws -> Loci_Trip_TripDraft {
    let fresh = try await service.trip(id: tripID)
    guard let request = StayTripPicker.setStay(stay, on: fresh) else { throw AddStayError.cityMissing(stay.cityName) }
    return try await service.setStay(request)
  }
}
