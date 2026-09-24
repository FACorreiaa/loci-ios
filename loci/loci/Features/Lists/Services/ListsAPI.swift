import Connect
import Foundation
import LociConnectProto

/// ListService (loci.list), one static func per RPC (web: lib/api/lists.ts).
///
/// Every call goes through `listRPC`, which turns a free-plan refusal into an
/// `EntitlementLimit` before the Connect error is flattened into an `APIError`
/// (that loses the `x-loci-entitlement` header).
nonisolated enum ListsAPI {
  private static let client = Loci_List_ListServiceClient(client: ConnectTransport.shared.protocolClient)
  private static let poi = Loci_Poi_PoiserviceClient(client: ConnectTransport.shared.protocolClient)

  /// web: useLists → GetLists{userId, limit 100, offset 0}.
  static func lists(userId: String) async throws -> [LociList] {
    let response = try await listRPC("Could not load your lists.", ListPayload.getLists(userId: userId)) {
      await client.getLists(request: $0, headers: [:])
    }
    return response.lists.map { LociList($0.list) }
  }

  /// web: useList → GetList{userId, listId, includeDetailedItems: true}. The
  /// server sends each row without its place, so each is filled from GetPOI.
  static func list(userId: String, id: String) async throws -> ListDetail {
    let response = try await listRPC("Could not load this list.", ListPayload.getList(userId: userId, listId: id)) {
      await client.getList(request: $0, headers: [:])
    }
    let items = response.list.items.map(\.listItem)
    let entries = await withTaskGroup(of: (Int, ListEntry).self) { group in
      for (index, item) in items.enumerated() { group.addTask { (index, await enrich(item)) } }
      var filled = [ListEntry?](repeating: nil, count: items.count)
      for await (index, entry) in group { filled[index] = entry }
      return filled.compactMap(\.self)
    }
    return ListDetail(list: LociList(response.list.list), entries: entries)
  }

  /// web: useCreateListMutation.
  static func create(userId: String, form: ListForm, cityId: String?) async throws -> LociList {
    let request = ListPayload.create(userId: userId, form: form, cityId: cityId)
    let response = try await listRPC("Could not create the list.", request) { await client.createList(request: $0, headers: [:]) }
    return LociList(response.list)
  }

  /// web: useUpdateListMutation (see `ListPayload.update` for what cannot change).
  static func update(userId: String, listId: String, form: ListForm) async throws -> LociList {
    let request = ListPayload.update(userId: userId, listId: listId, form: form)
    let response = try await listRPC("Could not save the list.", request) { await client.updateList(request: $0, headers: [:]) }
    return LociList(response.list)
  }

  /// web: useDeleteListMutation.
  static func delete(userId: String, listId: String) async throws {
    _ = try await listRPC("Could not delete the list.", ListPayload.delete(userId: userId, listId: listId)) {
      await client.deleteList(request: $0, headers: [:])
    }
  }

  /// web: useAddToListMutation.
  static func add(userId: String, listId: String, stop: Loci_Poi_POIDetailedInfo, destination: SearchDestination) async throws {
    guard let request = ListPayload.addItem(userId: userId, listId: listId, stop: stop, destination: destination) else {
      throw APIError.custom("This place can't go in a list yet.")
    }
    _ = try await listRPC("Could not add it to the list.", request) { await client.addListItem(request: $0, headers: [:]) }
  }

  /// web: useRemoveFromListMutation.
  static func remove(userId: String, listId: String, entry: ListEntry) async throws {
    let request = ListPayload.removeItem(userId: userId, listId: listId, entry: entry)
    _ = try await listRPC("Could not remove it from the list.", request) { await client.removeListItem(request: $0, headers: [:]) }
  }

  /// The stored place behind a row; the row alone when there is none.
  private static func enrich(_ item: Loci_List_ListItem) async -> ListEntry {
    var entry = ListEntry(item)
    let lookup = ListEntry.lookupID(item)
    guard SavedPlace.isStoredID(lookup) else { return entry }
    var request = Loci_Poi_GetPOIRequest()
    request.poiID = lookup
    guard let response = try? await rpc("Could not load this place.", request, { await poi.getPoi(request: $0, headers: [:]) }), response.hasPoi
    else { return entry }
    var stop = response.poi
    stop.id = item.itemID
    if stop.blurb.isEmpty { stop.description_p = item.itemAiDescription }
    entry.stop = stop
    return entry
  }

  /// `rpc` with the entitlement header read first, and a 501 in plain words.
  private static func listRPC<Input: Sendable, Output>(
    _ fallback: String,
    _ request: Input,
    _ call: @Sendable (Input) async -> ResponseMessage<Output>
  ) async throws -> Output {
    let response = await withAuthRetry { await call(request) }
    if let limit = EntitlementLimit.classify(response.error) { throw limit }
    if response.error?.code == .unimplemented { throw APIError.custom("\(fallback) This isn't available on the server yet.") }
    return try response.unwrap(fallback)
  }
}

/// What the Lists screens need from the server, behind a protocol so the
/// design previews and tests run without a session.
nonisolated protocol ListsService: Sendable {
  func lists() async throws -> [LociList]
  func list(id: String) async throws -> ListDetail
  func create(_ form: ListForm, cityId: String?) async throws -> LociList
  func update(_ listId: String, form: ListForm) async throws -> LociList
  func delete(_ listId: String) async throws
  func add(_ stop: Loci_Poi_POIDetailedInfo, destination: SearchDestination, to listId: String) async throws
  func remove(_ entry: ListEntry, from listId: String) async throws
}

nonisolated struct ConnectListsService: ListsService {
  private func userId() async -> String { await AuthSessionManager.shared.currentUserID ?? "me" }

  func lists() async throws -> [LociList] { try await ListsAPI.lists(userId: userId()) }
  func list(id: String) async throws -> ListDetail { try await ListsAPI.list(userId: userId(), id: id) }
  func create(_ form: ListForm, cityId: String?) async throws -> LociList { try await ListsAPI.create(userId: userId(), form: form, cityId: cityId) }
  func update(_ listId: String, form: ListForm) async throws -> LociList { try await ListsAPI.update(userId: userId(), listId: listId, form: form) }
  func delete(_ listId: String) async throws { try await ListsAPI.delete(userId: userId(), listId: listId) }
  func add(_ stop: Loci_Poi_POIDetailedInfo, destination: SearchDestination, to listId: String) async throws {
    try await ListsAPI.add(userId: userId(), listId: listId, stop: stop, destination: destination)
  }
  func remove(_ entry: ListEntry, from listId: String) async throws { try await ListsAPI.remove(userId: userId(), listId: listId, entry: entry) }
}
