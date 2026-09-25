import Foundation
import LociConnectProto
import SwiftProtobuf

/// A place from search, Saved or a list turned into a `TripStop`
/// (web: AddToTripButton's `stop`). The editor has its own private
/// `stop(from:orderIndex:)` for the place picker; this one is for places that
/// arrive from outside the trip, so it carries the recommendation trace and
/// the rationale, and it copes with places that were never stored.
///
/// TripStop has no coordinates: the server fills `poi` (and so the map pin)
/// from `poi_id` when that names a stored place. A name-only stop keeps its
/// name and notes and simply has no pin.
nonisolated enum TripStopBuilder {
  /// trip.proto: name 1…300, notes ≤ 4000, poi_id ≤ 100.
  static let nameLimit = 300
  static let notesLimit = 4000
  static let fallbackName = "Saved place"
  static let fallbackNotes = "Added from Loci"

  static func stop(from poi: Loci_Poi_POIDetailedInfo, orderIndex: Int, id: String = UUID().uuidString.lowercased()) -> Loci_Trip_TripStop {
    var stop = Loci_Trip_TripStop()
    stop.id = id
    // The handler hydrates `poi` from a stored id only; anything else would be
    // a dangling reference, so a name-keyed place goes in by name.
    if SavedPlace.isStoredID(poi.id) { stop.poiID = poi.id }
    stop.orderIndex = Int32(max(orderIndex, 0))
    stop.name = name(for: poi)
    stop.notes = notes(for: poi)
    if poi.hasRecommendationTrace { stop.recommendationTrace = poi.recommendationTrace }
    return stop
  }

  static func name(for poi: Loci_Poi_POIDetailedInfo) -> String {
    let trimmed = poi.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return String((trimmed.isEmpty ? fallbackName : trimmed).prefix(nameLimit))
  }

  /// web: `recommendation_rationale || description_poi || "Added from Discover"`,
  /// with the plain description as a second chance before the fallback.
  static func notes(for poi: Loci_Poi_POIDetailedInfo) -> String {
    let candidates = [poi.recommendationRationale, poi.descriptionPoi, poi.description_p]
    let first = candidates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    return String((first ?? fallbackNotes).prefix(notesLimit))
  }
}
