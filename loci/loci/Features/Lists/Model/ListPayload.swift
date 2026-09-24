import Foundation
import LociConnectProto

/// What the create/edit sheet holds (web: the ListsPage modal's signals).
nonisolated struct ListForm: Equatable, Sendable {
  var name = ""
  var description = ""
  var isItinerary = false
  var isPublic = false

  init(name: String = "", description: String = "", isItinerary: Bool = false, isPublic: Bool = false) {
    self.name = name
    self.description = description
    self.isItinerary = isItinerary
    self.isPublic = isPublic
  }

  init(_ list: LociList) { self.init(name: list.name, description: list.description, isItinerary: list.isItinerary, isPublic: list.isPublic) }

  /// Name is the one required field (web: `required`, trimmed before submit).
  var isValid: Bool { !trimmedName.isEmpty }
  var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// The inline "New list" in Add to list (web: AddToListButton.createNewList).
  static func quick(name: String, for placeName: String) -> ListForm { ListForm(name: name, description: "List created for \(placeName)") }
}

/// The ListService request builders, kept pure so the fields each RPC gets are
/// tested (web: lib/api/lists.ts). `userId` is required non-empty by
/// validation and ignored by the server, which reads the caller from the token.
nonisolated enum ListPayload {
  /// The server caps GetLists at 200; web asks for 100.
  static let pageLimit: Int32 = 100
  static let maxDescription = 4000

  static func getLists(userId: String) -> Loci_List_GetListsRequest {
    var request = Loci_List_GetListsRequest()
    request.userID = userId
    request.limit = pageLimit
    request.offset = 0
    return request
  }

  static func getList(userId: String, listId: String) -> Loci_List_GetListRequest {
    var request = Loci_List_GetListRequest()
    request.userID = userId
    request.listID = listId
    request.includeDetailedItems = true
    return request
  }

  /// web: useCreateListMutation. `cityId` is sent only when it names a real
  /// city: the handler ignores anything else, and a stop's city id is the one
  /// place iOS knows it.
  static func create(userId: String, form: ListForm, cityId: String? = nil) -> Loci_List_CreateListRequest {
    var request = Loci_List_CreateListRequest()
    request.userID = userId
    request.name = form.trimmedName
    request.description_p = form.trimmedDescription
    request.cityID = realUUID(cityId) ?? ""
    request.isItinerary = form.isItinerary
    request.isPublic = form.isPublic
    return request
  }

  /// web: useUpdateListMutation. `UpdateListRequest` has no `is_itinerary`
  /// field, so the kind cannot change after creation (web silently drops it;
  /// here the toggle is locked on edit). Empty strings mean "leave as is" to
  /// the handler, so a description cannot be cleared either.
  static func update(userId: String, listId: String, form: ListForm) -> Loci_List_UpdateListRequest {
    var request = Loci_List_UpdateListRequest()
    request.userID = userId
    request.listID = listId
    request.name = form.trimmedName
    request.description_p = form.trimmedDescription
    request.isPublic = form.isPublic
    return request
  }

  static func delete(userId: String, listId: String) -> Loci_List_DeleteListRequest {
    var request = Loci_List_DeleteListRequest()
    request.userID = userId
    request.listID = listId
    return request
  }

  /// web: useAddToListMutation from AddToListButton. Nil for a place with no
  /// stored id: the handler parses `item_id` as a UUID, so a name-keyed stop
  /// cannot go in a list.
  static func addItem(
    userId: String,
    listId: String,
    stop: Loci_Poi_POIDetailedInfo,
    destination: SearchDestination
  ) -> Loci_List_AddListItemRequest? {
    guard canAdd(stop) else { return nil }
    var request = Loci_List_AddListItemRequest()
    request.userID = userId
    request.listID = listId
    request.itemID = stop.id
    request.contentType = contentType(for: destination)
    request.position = 0
    request.notes = ""
    // The server sends no place content back with a list, so the blurb rides
    // along as the row's description (web sends none).
    let blurb = stop.blurb
    if !blurb.isEmpty { request.itemAiDescription = String(blurb.prefix(maxDescription)) }
    if stop.hasRecommendationTrace { request.recommendationTrace = stop.recommendationTrace }
    return request
  }

  static func removeItem(userId: String, listId: String, entry: ListEntry) -> Loci_List_RemoveListItemRequest {
    var request = Loci_List_RemoveListItemRequest()
    request.userID = userId
    request.listID = listId
    request.itemID = entry.itemID
    request.contentType = entry.contentType
    return request
  }

  static func canAdd(_ stop: Loci_Poi_POIDetailedInfo) -> Bool { realUUID(stop.id) != nil }

  /// web: contentTypeToProto, keyed on the result's domain.
  static func contentType(for destination: SearchDestination) -> Loci_List_ContentType {
    switch destination {
    case .hotels: .hotel
    case .restaurants: .restaurant
    case .activities, .itinerary: .poi
    }
  }

  static func destination(for contentType: Loci_List_ContentType) -> SearchDestination {
    switch contentType {
    case .hotel: .hotels
    case .restaurant: .restaurants
    default: .activities
    }
  }

  /// Web's `content_type` analytics value.
  static func analyticsName(_ contentType: Loci_List_ContentType) -> String {
    switch contentType {
    case .hotel: "hotel"
    case .restaurant: "restaurant"
    case .itinerary: "itinerary"
    default: "poi"
    }
  }

  /// A UUID that is not the nil UUID (what the server sends for "none").
  static func realUUID(_ value: String?) -> String? {
    guard let value, let uuid = UUID(uuidString: value), uuid != nilUUID else { return nil }
    return value
  }

  private static let nilUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}
