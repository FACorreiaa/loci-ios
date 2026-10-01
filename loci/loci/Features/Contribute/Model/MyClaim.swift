import Foundation
import LociConnectProto
import SwiftProtobuf

/// One of the scout's own field reports, as ListMyClaims returns it: the place,
/// what was reported, and what became of it.
nonisolated struct MyClaim: Identifiable, Equatable, Sendable {
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

  var fieldLabel: String { PlaceFactVocabulary.label(field) }
  var statusText: String { Self.statusText(status) }

  /// The same words the claim form uses for an outcome.
  static func statusText(_ status: Loci_Place_PlaceClaimStatus) -> String {
    switch status {
    case .pending: "Waiting on a second scout"
    case .accepted: "Verified"
    case .contradicted: "Reports differ"
    case .expired: "Expired"
    case .unspecified, .UNRECOGNIZED: "Recorded"
    }
  }

  var symbol: String {
    switch status {
    case .accepted: "checkmark.shield.fill"
    case .contradicted: "exclamationmark.circle"
    case .expired: "clock.badge.xmark"
    case .pending, .unspecified, .UNRECOGNIZED: "clock"
    }
  }
}
