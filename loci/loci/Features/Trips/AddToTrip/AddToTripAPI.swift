import Connect
import Foundation
import LociConnectProto

/// TripService for Add to trip, one static func per RPC (web: lib/api/trips.ts).
/// Its own client, so this folder stands apart from the trip editor's.
nonisolated enum AddToTripAPI {
  private static let client = Loci_Trip_TripServiceClient(client: ConnectTransport.shared.protocolClient)

  /// web: useTrips.
  static func trips() async throws -> [Loci_Trip_TripDraft] {
    try await rpc("Could not load your trips.", AddToTripPayload.listTrips()) { await client.listTrips(request: $0, headers: [:]) }.trips
  }

  /// web: useTrip. Read right before an add, for the version.
  static func trip(id: String) async throws -> Loci_Trip_TripDraft {
    try await rpc("Could not load the trip.", AddToTripPayload.getTrip(id: id)) { await client.getTrip(request: $0, headers: [:]) }
  }

  /// web: useAddStop. A stale `baseVersion` (the handler's FailedPrecondition)
  /// comes back as `AddToTripError.staleVersion`, before the Connect error is
  /// flattened, so the flow can re-read the trip and try once more.
  static func addStop(_ request: Loci_Trip_AddStopRequest) async throws -> Loci_Trip_TripDraft {
    let response = await withAuthRetry { await client.addStop(request: request, headers: [:]) }
    if response.error?.code == .failedPrecondition { throw AddToTripError.staleVersion }
    return try response.unwrap("Could not add the place.")
  }

  /// web: useSaveTrip with baseVersion 0 (a new trip).
  static func createTrip(_ request: Loci_Trip_SaveTripRequest) async throws -> Loci_Trip_TripDraft {
    try await rpc("Could not create the trip.", request) { await client.saveTrip(request: $0, headers: [:]) }
  }
}

nonisolated enum AddToTripError: Error, Equatable, LocalizedError {
  /// The trip changed between the read and the write.
  case staleVersion
  /// The chosen day is gone from the trip (deleted on another device).
  case dayMissing

  var errorDescription: String? {
    switch self {
    case .staleVersion: "This trip just changed on another device. Open it and try again."
    case .dayMissing: "That day is no longer in the trip. Pick another one."
    }
  }
}

/// What Add to trip needs from the server, behind a protocol so the design
/// preview and the tests run without a session.
nonisolated protocol AddToTripService: Sendable {
  func trips() async throws -> [Loci_Trip_TripDraft]
  func trip(id: String) async throws -> Loci_Trip_TripDraft
  func addStop(_ request: Loci_Trip_AddStopRequest) async throws -> Loci_Trip_TripDraft
  func createTrip(_ request: Loci_Trip_SaveTripRequest) async throws -> Loci_Trip_TripDraft
}

nonisolated struct ConnectAddToTripService: AddToTripService {
  func trips() async throws -> [Loci_Trip_TripDraft] { try await AddToTripAPI.trips() }
  func trip(id: String) async throws -> Loci_Trip_TripDraft { try await AddToTripAPI.trip(id: id) }
  func addStop(_ request: Loci_Trip_AddStopRequest) async throws -> Loci_Trip_TripDraft { try await AddToTripAPI.addStop(request) }
  func createTrip(_ request: Loci_Trip_SaveTripRequest) async throws -> Loci_Trip_TripDraft { try await AddToTripAPI.createTrip(request) }
}

/// Where the place landed: the trip as the server now has it, and the day.
nonisolated struct AddedStop: Equatable, Sendable {
  let trip: Loci_Trip_TripDraft
  let dayNumber: Int32
}

nonisolated enum AddToTripFlow {
  /// Read the trip for a fresh version, add, and on a stale version read and
  /// add once more. Two adds in a row, or an edit on another device between
  /// the read and the write, then still land.
  static func add(
    _ poi: Loci_Poi_POIDetailedInfo,
    tripID: String,
    dayNumber: Int32,
    service: some AddToTripService
  ) async throws -> AddedStop {
    do {
      return try await attempt(poi, tripID: tripID, dayNumber: dayNumber, service: service)
    } catch AddToTripError.staleVersion {
      return try await attempt(poi, tripID: tripID, dayNumber: dayNumber, service: service)
    }
  }

  private static func attempt(
    _ poi: Loci_Poi_POIDetailedInfo,
    tripID: String,
    dayNumber: Int32,
    service: some AddToTripService
  ) async throws -> AddedStop {
    let fresh = try await service.trip(id: tripID)
    guard let request = AddToTripPayload.addStop(to: fresh, dayNumber: dayNumber, poi: poi) else { throw AddToTripError.dayMissing }
    let updated = try await service.addStop(request)
    return AddedStop(trip: updated, dayNumber: dayNumber)
  }
}
