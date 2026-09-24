import Foundation
import LociConnectProto

/// Where a feed row goes when it is tapped (web: lib/recents/activity-link.ts `activityHref`).
nonisolated enum ActivityDestination: Hashable, Sendable {
  /// A result page for the prompt's session. The message rides along so a
  /// session that cannot be restored can be run again (web's `?message=`).
  case search(SessionLink, message: String)
  /// A nearby prompt with no session: the Near me map, which has no city to take.
  case nearby
  /// A kept itinerary: the saved row's id, and the session it came from if any.
  case savedItinerary(id: String, sessionId: String)
  /// A favourited place, opened on what the favourite kept.
  case favourite(Loci_Favorites_V1_FavoriteItem)

  /// Nil for a kind this build does not know: the row shows, but opens nothing.
  init?(_ entry: ActivityEntry) {
    switch entry.kind {
    case .prompt: self = Self.prompt(entry)
    case .savedItinerary:
      // The feed row's id is the saved itinerary's id; its ref is the session.
      self = .savedItinerary(id: entry.id, sessionId: entry.refId)
    case .favourite:
      guard entry.detail != "itinerary" else {
        self = .savedItinerary(id: entry.refId, sessionId: "")
        return
      }
      self = .favourite(Self.favourite(entry))
    case .other: return nil
    }
  }

  /// Web's `getDomainRoute` for the page, plus "nearby", which it would drop on
  /// an itinerary. Near me here is location-only, so a nearby prompt that has a
  /// session opens that session's result page, where its places are.
  private static func prompt(_ entry: ActivityEntry) -> ActivityDestination {
    if entry.detail == "nearby", entry.refId.isEmpty { return .nearby }
    let link = SessionLink(
      destination: SearchDestination(domain: entry.detail),
      sessionId: entry.refId,
      cityName: ActivityFeed.nonEmpty(entry.cityName),
      domain: entry.detail
    )
    return .search(link, message: entry.label)
  }

  /// A favourite as `SavedPlaceDetailView` takes it: the feed row's id is the
  /// favourite's, its ref is the item's, its label is the name.
  private static func favourite(_ entry: ActivityEntry) -> Loci_Favorites_V1_FavoriteItem {
    var item = Loci_Favorites_V1_FavoriteItem()
    item.id = entry.id
    item.itemID = entry.refId
    item.itemName = entry.label
    item.cityName = entry.cityName
    item.contentType =
      switch entry.detail {
      case "hotel": .hotel
      case "restaurant": .restaurant
      default: .poi
      }
    return item
  }
}

nonisolated enum SavedItineraryMatch {
  /// The saved itinerary a feed row names: by id first, then by the session it came from.
  static func find(in itineraries: [Loci_Itinerary_UserSavedItinerary], id: String, sessionId: String) -> Loci_Itinerary_UserSavedItinerary? {
    if !id.isEmpty, let hit = itineraries.first(where: { $0.id == id }) { return hit }
    guard !sessionId.isEmpty else { return nil }
    return itineraries.first { $0.hasSessionID && $0.sessionID == sessionId }
  }
}
