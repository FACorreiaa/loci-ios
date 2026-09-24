import Foundation
import LociConnectProto
import SwiftProtobuf

/// One of the user's lists as the screens read it (web: the `list` object
/// `useLists` unwraps from `ListWithItems`).
nonisolated struct LociList: Identifiable, Hashable, Sendable {
  let id: String
  var name: String
  var description: String
  var isPublic: Bool
  var isItinerary: Bool
  /// Nil when the list has no city: the server sends the nil UUID for that.
  var cityID: String?
  /// The server leaves `item_count` at 0 today, so 0 means "not known", not "empty".
  var itemCount: Int
  var createdAt: Date?

  init(
    id: String,
    name: String,
    description: String = "",
    isPublic: Bool = false,
    isItinerary: Bool = false,
    cityID: String? = nil,
    itemCount: Int = 0,
    createdAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.isPublic = isPublic
    self.isItinerary = isItinerary
    self.cityID = cityID
    self.itemCount = itemCount
    self.createdAt = createdAt
  }

  init(_ list: Loci_List_List) {
    self.init(
      id: list.id,
      name: list.name,
      description: list.description_p,
      isPublic: list.isPublic,
      isItinerary: list.isItinerary,
      cityID: ListPayload.realUUID(list.cityID),
      itemCount: Int(list.itemCount),
      createdAt: list.hasCreatedAt ? list.createdAt.date : nil
    )
  }
}

/// A place in a list: what the list row kept, and the place to show for it.
/// The server sends only the row (no POI content, whatever
/// `include_detailed_items` says), so `stop` starts as a snapshot and the
/// service fills it from the stored POI.
nonisolated struct ListEntry: Identifiable, Hashable, Sendable {
  let itemID: String
  var contentType: Loci_List_ContentType
  var notes: String
  var stop: Loci_Poi_POIDetailedInfo

  var id: String { itemID }

  /// Result pages pick card layout and meta line from the domain.
  var destination: SearchDestination { ListPayload.destination(for: contentType) }

  init(itemID: String, contentType: Loci_List_ContentType = .poi, notes: String = "", stop: Loci_Poi_POIDetailedInfo) {
    self.itemID = itemID
    self.contentType = contentType
    self.notes = notes
    self.stop = stop
  }

  init(_ item: Loci_List_ListItem) {
    var stop = Loci_Poi_POIDetailedInfo()
    stop.id = item.itemID
    stop.name = ListEntry.unnamed
    if !item.itemAiDescription.isEmpty { stop.description_p = item.itemAiDescription }
    self.init(itemID: item.itemID, contentType: item.contentType, notes: item.notes, stop: stop)
  }

  /// The id to look the place up by: the POI id when the row has one.
  static func lookupID(_ item: Loci_List_ListItem) -> String { ListPayload.realUUID(item.poiID) ?? item.itemID }

  static let unnamed = "Saved place"
}

/// A list with its places (GetList).
nonisolated struct ListDetail: Hashable, Sendable {
  var list: LociList
  var entries: [ListEntry]

  /// Only the places with a position go on the map.
  var mappable: [Loci_Poi_POIDetailedInfo] { entries.map(\.stop).filter(GoogleMapsRoute.hasCoordinate) }
}

// MARK: - Tabs (web: routes/lists/index.tsx activeTab)

nonisolated enum ListsTab: String, CaseIterable, Identifiable, Sendable {
  case all, custom, itineraries

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: "All"
    case .custom: "Custom"
    case .itineraries: "Itineraries"
    }
  }

  /// Web's empty-state heading per tab.
  var emptyTitle: String {
    switch self {
    case .all: "No lists yet"
    case .custom: "No custom lists yet"
    case .itineraries: "No itineraries yet"
    }
  }

  func includes(_ list: LociList) -> Bool {
    switch self {
    case .all: true
    case .custom: !list.isItinerary
    case .itineraries: list.isItinerary
    }
  }
}

nonisolated enum ListFilter {
  static func apply(_ lists: [LociList], tab: ListsTab) -> [LociList] { lists.filter(tab.includes) }

  static func counts(_ lists: [LociList]) -> [ListsTab: Int] {
    Dictionary(uniqueKeysWithValues: ListsTab.allCases.map { tab in (tab, lists.count(where: tab.includes)) })
  }
}
