import CoreLocation
import Foundation
import LociConnectProto
import SwiftProtobuf

/// Request builders for PlaceIntelligenceService and the missing-place
/// search, kept pure so the tests can read exactly what goes on the wire.
nonisolated enum ContributePayload {
  static let taskLimit: Int32 = 40
  static let pendingLimit: Int32 = 20
  static let searchRadiusKm = 25.0
  static let searchResultLimit = 5
  /// The SearchPOI handler ignores `city_name` on a hybrid search, but the
  /// request validator requires one (min_len 1), so a location search with no
  /// city known sends this.
  static let nearbyCityPlaceholder = "nearby"

  /// Reports hang off a stored POI (the handler parses `poi_id` as a UUID and
  /// checks it exists), the same rule as Add to list and Reviews.
  static func canReport(poiID: String) -> Bool { ListPayload.realUUID(poiID) != nil }

  static func canReport(_ stop: Loci_Poi_POIDetailedInfo) -> Bool { canReport(poiID: stop.id) }

  static func tasks() -> Loci_Place_ListVerificationTasksRequest {
    var request = Loci_Place_ListVerificationTasksRequest()
    request.limit = taskLimit
    return request
  }

  static func pendingPlaces() -> Loci_Place_ListPendingPlacesRequest {
    var request = Loci_Place_ListPendingPlacesRequest()
    request.limit = pendingLimit
    return request
  }

  /// One claim: a fresh client id per claim and "observed now", as web sends it.
  static func claim(
    poiID: String,
    field: Loci_Place_PlaceFactField,
    value: String,
    now: Date = .now,
    clientClaimID: String = UUID().uuidString.lowercased()
  ) -> Loci_Place_SubmitPlaceClaimRequest {
    var request = Loci_Place_SubmitPlaceClaimRequest()
    request.clientClaimID = clientClaimID
    request.poiID = poiID
    request.field = field
    request.value = value
    request.observedAt = Google_Protobuf_Timestamp(date: now)
    return request
  }

  /// Trimmed name and city; the kind only when there is one.
  static func submitPlace(_ draft: PlaceDraft) -> Loci_Place_SubmitPlaceRequest {
    var request = Loci_Place_SubmitPlaceRequest()
    request.clientSubmissionID = draft.submissionID
    request.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    request.cityName = draft.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
    let category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
    if !category.isEmpty { request.category = category }
    return request
  }

  static func confirm(submissionID: String) -> Loci_Place_ConfirmPlaceRequest {
    var request = Loci_Place_ConfirmPlaceRequest()
    request.submissionID = submissionID
    return request
  }

  /// web: MissingPlaceCard. Hybrid within 25 km when the location is known,
  /// otherwise semantic in the named city. Nil when there is nothing to search
  /// with: no query, or neither a location nor a city.
  static func search(query: String, city: String, coordinate: CLLocationCoordinate2D?) -> Loci_Poi_SearchPOIRequest? {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty, coordinate != nil || !city.isEmpty else { return nil }
    var request = Loci_Poi_SearchPOIRequest()
    request.query = query
    if let coordinate {
      request.latitude = coordinate.latitude
      request.longitude = coordinate.longitude
      request.radiusKm = searchRadiusKm
      request.searchType = "hybrid"
      request.cityName = city.isEmpty ? nearbyCityPlaceholder : city
    } else {
      request.searchType = "semantic"
      request.cityName = city
    }
    return request
  }

  /// "cafe · Rua da Rosa 12" (web: category, then address or city).
  static func searchSubtitle(_ poi: Loci_Poi_POIDetailedInfo) -> String {
    let place = poi.address.isEmpty ? poi.city : poi.address
    return [poi.category, place].filter { !$0.isEmpty }.joined(separator: " · ")
  }
}
