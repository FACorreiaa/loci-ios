import LociConnectProto
import SwiftUI

/// The user's lists, shared by the Saved segment and Profile › Lists. A failed
/// load with nothing on screen is an error state; with rows on screen it is an
/// alert and the rows stay. A free-plan refusal is `limit`, shown as its own sheet.
@MainActor @Observable final class ListsStore {
  enum Phase: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  private(set) var lists: [LociList] = []
  private(set) var phase = Phase.idle
  var error: String?
  var limit: EntitlementLimit?
  /// The create/edit sheet: nil closed, `.new` or `.edit(list)`.
  var editor: ListEditor?
  /// The list waiting on the delete confirmation.
  var pendingDelete: LociList?
  var tab = ListsTab.all

  var visible: [LociList] { ListFilter.apply(lists, tab: tab) }

  let service: ListsService

  init(service: ListsService = ConnectListsService()) { self.service = service }

  func loadIfNeeded() async { if phase == .idle { await load() } }

  func load() async {
    if lists.isEmpty { phase = .loading }
    do {
      lists = try await service.lists()
      phase = .loaded
    } catch {
      guard !error.isCancellation else {
        if phase == .loading { phase = .idle }
        return
      }
      if lists.isEmpty { phase = .failed(error.userMessage) } else { self.error = error.userMessage }
    }
  }

  /// Create or update. Returns whether the sheet can close; a failure keeps it
  /// open with what was typed (web closes it and only logs).
  func save(_ form: ListForm, editing: LociList?) async -> Bool {
    do {
      if let editing {
        let saved = try await service.update(editing.id, form: form)
        replace(editing.id, with: saved, fallback: form)
      } else {
        let created = try await service.create(form, cityId: nil)
        lists.insert(created, at: 0)
        phase = .loaded
      }
      return true
    } catch {
      report(error)
      return false
    }
  }

  /// Optimistic, as web: the row goes at once and comes back if the server says no.
  func delete(_ list: LociList) async {
    guard let index = lists.firstIndex(of: list) else { return }
    lists.remove(at: index)
    do { try await service.delete(list.id) } catch {
      lists.insert(list, at: min(index, lists.count))
      report(error)
    }
  }

  func report(_ error: Error) {
    if let limit = error as? EntitlementLimit { self.limit = limit } else if !error.isCancellation { self.error = error.userMessage }
  }

  /// The server's echo when it sends one; else the old row with the form applied.
  private func replace(_ id: String, with saved: LociList, fallback form: ListForm) {
    guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
    if saved.id == id {
      lists[index] = saved
    } else {
      lists[index].name = form.trimmedName
      if !form.trimmedDescription.isEmpty { lists[index].description = form.trimmedDescription }
      lists[index].isPublic = form.isPublic
    }
  }
}

/// One list and its places.
@MainActor @Observable final class ListDetailStore {
  enum Phase: Equatable {
    case loading, loaded
    case failed(String)
  }

  let listID: String
  private(set) var detail: ListDetail?
  private(set) var phase = Phase.loading
  var error: String?

  private let service: ListsService

  init(listID: String, initial: LociList? = nil, service: ListsService = ConnectListsService()) {
    self.listID = listID
    self.service = service
    if let initial { detail = ListDetail(list: initial, entries: []) }
  }

  func load() async {
    do {
      detail = try await service.list(id: listID)
      phase = .loaded
    } catch {
      guard !error.isCancellation else { return }
      if phase == .loaded { self.error = error.userMessage } else { phase = .failed(error.userMessage) }
    }
  }

  /// Optimistic; the row comes back where it was if the server refuses.
  func remove(_ entry: ListEntry) async {
    guard var detail, let index = detail.entries.firstIndex(of: entry) else { return }
    detail.entries.remove(at: index)
    self.detail = detail
    do { try await service.remove(entry, from: listID) } catch {
      self.detail?.entries.insert(entry, at: min(index, self.detail?.entries.count ?? 0))
      if !error.isCancellation { self.error = error.userMessage }
    }
  }
}

/// Add to list, from a place's detail (web: AddToListButton).
@MainActor @Observable final class AddToListStore {
  enum Phase: Equatable {
    case loading, loaded
    case failed(String)
  }

  let stop: Loci_Poi_POIDetailedInfo
  let destination: SearchDestination
  private(set) var lists: [LociList] = []
  private(set) var phase = Phase.loading
  /// The list being written to, so its row shows progress and taps don't double up.
  private(set) var busyID: String?
  private(set) var isCreating = false
  var error: String?
  var limit: EntitlementLimit?

  private let service: ListsService

  init(stop: Loci_Poi_POIDetailedInfo, destination: SearchDestination, service: ListsService = ConnectListsService()) {
    self.stop = stop
    self.destination = destination
    self.service = service
  }

  var placeName: String { stop.name.isEmpty ? ListEntry.unnamed : stop.name }

  func load() async {
    do {
      lists = try await service.lists()
      phase = .loaded
    } catch {
      guard !error.isCancellation else { return }
      phase = .failed(error.userMessage)
    }
  }

  /// True once the place is in the list.
  func add(to list: LociList) async -> Bool {
    guard busyID == nil else { return false }
    busyID = list.id
    defer { busyID = nil }
    do {
      try await service.add(stop, destination: destination, to: list.id)
      let contentType = ListPayload.contentType(for: destination)
      Analytics.capture(.poiSaved, ["surface": "list", "content_type": ListPayload.analyticsName(contentType)])
      return true
    } catch {
      report(error)
      return false
    }
  }

  /// web: createNewList — create with "List created for {name}", then add. The
  /// stop's city goes with it when the place knows one.
  func createAndAdd(name: String) async -> Bool {
    let form = ListForm.quick(name: name, for: placeName)
    guard form.isValid, !isCreating else { return false }
    isCreating = true
    defer { isCreating = false }
    do {
      let created = try await service.create(form, cityId: stop.cityID)
      lists.insert(created, at: 0)
      isCreating = false
      return await add(to: created)
    } catch {
      report(error)
      return false
    }
  }

  private func report(_ error: Error) {
    if let limit = error as? EntitlementLimit { self.limit = limit } else if !error.isCancellation { self.error = error.userMessage }
  }
}

/// What the create/edit sheet opens on.
nonisolated enum ListEditor: Identifiable, Hashable, Sendable {
  case new
  case edit(LociList)

  var id: String {
    switch self {
    case .new: "new"
    case .edit(let list): list.id
    }
  }

  var list: LociList? {
    if case .edit(let list) = self { return list }
    return nil
  }
}

nonisolated extension Error { var isCancellation: Bool { self is CancellationError || (self as? APIError) == .cancelled } }
