import Connect
import CoreLocation
import Foundation
import LociConnectProto
import MapKit

/// PlaceIntelligenceService (loci.place) for Contribute, one static func per
/// RPC, plus PoiService.SearchPOI for "Something we're missing".
/// GetPlaceFacts stays in ResultsAPI, next to the place detail that reads it.
nonisolated enum ContributeAPI {
  private static var places: Loci_Place_PlaceIntelligenceServiceClient { ResultsAPI.places }
  private static let poi = Loci_Poi_PoiserviceClient(client: ConnectTransport.shared.protocolClient)

  /// web: useVerificationTasks → ListVerificationTasks{limit: 40}.
  static func tasks() async throws -> [VerificationTask] {
    let response = try await rpc("Could not load places to verify.", ContributePayload.tasks()) {
      await places.listVerificationTasks(request: $0, headers: [:])
    }
    return response.tasks.map(VerificationTask.init)
  }

  /// web: useContributorProfile → GetMyContributorProfile{}.
  static func profile() async throws -> ContributorProfile {
    let response = try await rpc("Could not load your scout profile.", Loci_Place_GetMyContributorProfileRequest()) {
      await places.getMyContributorProfile(request: $0, headers: [:])
    }
    return ContributorProfile(response)
  }

  /// web: usePendingPlaces → ListPendingPlaces{limit: 20}.
  static func pendingPlaces() async throws -> [PendingPlace] {
    let response = try await rpc("Could not load places waiting on a scout.", ContributePayload.pendingPlaces()) {
      await places.listPendingPlaces(request: $0, headers: [:])
    }
    return response.places.map(PendingPlace.init)
  }

  /// web: useSubmitPlaceClaims. One SubmitPlaceClaim per answer, all at once;
  /// any failure fails the report (web's Promise.all). Returns the best status.
  static func submitClaims(poiID: String, field: Loci_Place_PlaceFactField, values: [String]) async throws -> ClaimResult {
    let requests = values.map { ContributePayload.claim(poiID: poiID, field: field, value: $0) }
    let results = try await withThrowingTaskGroup(of: (Int, ClaimResult).self) { group in
      for (index, request) in requests.enumerated() {
        group.addTask {
          let response = try await rpc("Could not file your report.", request) { await places.submitPlaceClaim(request: $0, headers: [:]) }
          return (index, ClaimResult(claimID: response.claimID, status: response.status))
        }
      }
      var collected: [(Int, ClaimResult)] = []
      for try await result in group { collected.append(result) }
      return collected.sorted { $0.0 < $1.0 }.map(\.1)
    }
    return ClaimResult.best(results)
  }

  /// web: useSubmitPlace, with the draft's own client id so a retry is a repeat.
  static func submitPlace(_ draft: PlaceDraft) async throws -> PlaceSubmissionResult {
    let response = try await rpc("Could not add this place.", ContributePayload.submitPlace(draft)) {
      await places.submitPlace(request: $0, headers: [:])
    }
    return PlaceSubmissionResult(
      submissionID: response.submissionID,
      promoted: response.status == .accepted,
      confirmationsNeeded: Int(response.confirmationsNeeded)
    )
  }

  /// web: useConfirmPlace.
  static func confirmPlace(submissionID: String) async throws -> PlaceSubmissionResult {
    let response = try await rpc("That did not go through. Try again.", ContributePayload.confirm(submissionID: submissionID)) {
      await places.confirmPlace(request: $0, headers: [:])
    }
    return PlaceSubmissionResult(
      submissionID: submissionID,
      promoted: response.status == .accepted,
      confirmationsNeeded: Int(response.confirmationsNeeded)
    )
  }

  /// web: MissingPlaceCard → searchPOIs, top five.
  static func searchPlaces(query: String, city: String, coordinate: CLLocationCoordinate2D?) async throws -> [Loci_Poi_POIDetailedInfo] {
    guard let request = ContributePayload.search(query: query, city: city, coordinate: coordinate) else { return [] }
    let response = try await rpc("We couldn't search places. Try again.", request) { await poi.searchPoi(request: $0, headers: [:]) }
    return Array(response.pois.prefix(ContributePayload.searchResultLimit))
  }

  /// Where the scout is, only when location is already allowed (Contribute
  /// never asks for it), with the city name when it can be worked out.
  static func searchContext() async -> ContributeSearchContext? {
    let status = CLLocationManager().authorizationStatus
    guard status == .authorizedWhenInUse || status == .authorizedAlways, let coordinate = try? await CurrentLocation.fetch(timeout: .seconds(6))
    else { return nil }
    let city = await cityName(near: coordinate)
    return ContributeSearchContext(coordinate: coordinate, city: city ?? "")
  }

  /// The city at a coordinate. Off the caller's actor: the request and its map
  /// items aren't Sendable, so only the name is handed back.
  @concurrent private static func cityName(near coordinate: CLLocationCoordinate2D) async -> String? {
    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
    return try? await request.mapItems.first?.addressRepresentations?.cityName
  }
}

nonisolated struct ContributeSearchContext: Sendable {
  let coordinate: CLLocationCoordinate2D
  let city: String
}

/// What Contribute needs from the server, behind a protocol so the design
/// previews and the tests run without a session.
nonisolated protocol ContributeService: Sendable {
  func tasks() async throws -> [VerificationTask]
  func profile() async throws -> ContributorProfile
  func pendingPlaces() async throws -> [PendingPlace]
  func submitClaims(poiID: String, field: Loci_Place_PlaceFactField, values: [String]) async throws -> ClaimResult
  func submitPlace(_ draft: PlaceDraft) async throws -> PlaceSubmissionResult
  func confirmPlace(submissionID: String) async throws -> PlaceSubmissionResult
  func searchPlaces(query: String, city: String, coordinate: CLLocationCoordinate2D?) async throws -> [Loci_Poi_POIDetailedInfo]
  func searchContext() async -> ContributeSearchContext?
}

nonisolated struct ConnectContributeService: ContributeService {
  func tasks() async throws -> [VerificationTask] { try await ContributeAPI.tasks() }
  func profile() async throws -> ContributorProfile { try await ContributeAPI.profile() }
  func pendingPlaces() async throws -> [PendingPlace] { try await ContributeAPI.pendingPlaces() }
  func submitClaims(poiID: String, field: Loci_Place_PlaceFactField, values: [String]) async throws -> ClaimResult {
    try await ContributeAPI.submitClaims(poiID: poiID, field: field, values: values)
  }
  func submitPlace(_ draft: PlaceDraft) async throws -> PlaceSubmissionResult { try await ContributeAPI.submitPlace(draft) }
  func confirmPlace(submissionID: String) async throws -> PlaceSubmissionResult { try await ContributeAPI.confirmPlace(submissionID: submissionID) }
  func searchPlaces(query: String, city: String, coordinate: CLLocationCoordinate2D?) async throws -> [Loci_Poi_POIDetailedInfo] {
    try await ContributeAPI.searchPlaces(query: query, city: city, coordinate: coordinate)
  }
  func searchContext() async -> ContributeSearchContext? { await ContributeAPI.searchContext() }
}
