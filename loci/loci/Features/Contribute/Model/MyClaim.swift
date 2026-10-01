import Foundation
import LociConnectProto
import SwiftProtobuf

/// One of the scout's own field reports, as ListMyClaims returns it: the place,
/// what was reported, and what became of it.
nonisolated struct MyClaim: Identifiable, Hashable, Sendable {
  var id: String
  var poiID: String
  var placeName: String
  var field: Loci_Place_PlaceFactField
  var value: String
  var status: Loci_Place_PlaceClaimStatus
  var createdAt: Date?

  static let removedPlaceName = "A place since removed"

  init(
    id: String,
    poiID: String,
    placeName: String,
    field: Loci_Place_PlaceFactField,
    value: String,
    status: Loci_Place_PlaceClaimStatus,
    createdAt: Date? = nil
  ) {
    self.id = id
    self.poiID = poiID
    self.placeName = placeName.isEmpty ? Self.removedPlaceName : placeName
    self.field = field
    self.value = value
    self.status = status
    self.createdAt = createdAt
  }

  init(_ proto: Loci_Place_MyPlaceClaim) {
    self.init(
      id: proto.claimID,
      poiID: proto.poiID,
      placeName: proto.poiName,
      field: proto.field,
      value: proto.value,
      status: proto.status,
      createdAt: proto.hasCreatedAt ? proto.createdAt.date : nil
    )
  }

  /// Whether the row opens the place: it is a stored POI that still exists.
  var opensPlace: Bool { ContributePayload.canReport(poiID: poiID) && placeName != Self.removedPlaceName }

  var fieldLabel: String { PlaceFactVocabulary.label(field) }
  /// The option's label ("Gluten free"), or the value itself (opening hours).
  var valueText: String { PlaceFactVocabulary.displayValue(field, value) }
  var statusText: String { Self.statusText(status) }

  /// The claim form's outcome in one word: Verified, Noted (reports differ)
  /// or Recorded (waiting on a second scout, or a status this build doesn't
  /// know). An expired claim says Expired, as web's My reports does.
  static func statusText(_ status: Loci_Place_PlaceClaimStatus) -> String {
    if status == .expired { return "Expired" }
    switch ClaimOutcome(status) {
    case .verified: "Verified"
    case .contradicted: "Noted"
    case .recorded: "Recorded"
    }
  }

  var symbol: String {
    switch ClaimOutcome(status) {
    case .verified: "checkmark.shield.fill"
    case .contradicted: "exclamationmark.circle"
    case .recorded(let pending): pending ? "clock" : "checkmark.circle"
    }
  }
}

/// One page of ListMyClaims, and whether there is another.
nonisolated struct MyClaimsPage: Equatable, Sendable {
  var claims: [MyClaim]
  var total: Int
  var hasMore: Bool

  static let empty = MyClaimsPage(claims: [], total: 0, hasMore: false)

  init(claims: [MyClaim], total: Int, hasMore: Bool) {
    self.claims = claims
    self.total = max(0, total)
    self.hasMore = hasMore
  }

  init(_ response: Loci_Place_ListMyClaimsResponse, page: Int, limit: Int32 = ContributePayload.myClaimsLimit) {
    let claims = response.claims.map(MyClaim.init)
    self.init(
      claims: claims,
      total: Int(response.total),
      hasMore: ContributePayload.claimsHaveMore(page: page, received: claims.count, total: Int(response.total), limit: limit)
    )
  }
}
