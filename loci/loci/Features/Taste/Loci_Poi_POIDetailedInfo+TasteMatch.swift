import Foundation
import LociConnectProto

/// How well a place fits the traveller, as the server scored it (web:
/// lib/taste/match.ts). Unset when it could not be scored — signed out, too
/// little feedback yet, personalization off — and then nothing is shown.
nonisolated extension Loci_Poi_POIDetailedInfo {
  /// Cards only point at a strong match; the detail sheet shows any.
  static let cardMatchThreshold: Float = 0.6

  var matchPercent: Int? {
    hasTasteMatch ? Int((tasteMatch.score * 100).rounded()) : nil
  }

  var matchLabel: String? {
    matchPercent.map { "\($0)% match" }
  }

  var showsMatchOnCard: Bool {
    hasTasteMatch && tasteMatch.score >= Self.cardMatchThreshold
  }

  /// The reasons worth showing, blank ones dropped.
  var matchReasons: [String] {
    tasteMatch.reasons.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  }
}
