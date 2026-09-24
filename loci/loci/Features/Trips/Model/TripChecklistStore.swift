import Connect
import Foundation
import LociConnectProto
import Observation

/// A trip's packing list, expenses and packing suggestions, synced through
/// TripService's checklist RPCs.
///
/// Every edit is optimistic: the list changes at once and the RPC follows. A
/// failure puts back only the item that failed, so two quick edits cannot
/// undo each other. The checklist has its own versioning on the server (none
/// of these calls take a `baseVersion`), so ticking an item never conflicts
/// with a stop edit.
@MainActor @Observable final class TripChecklistStore {
  enum Availability: Equatable {
    case loading
    case ready
    /// The server does not have the checklist RPCs yet (Unimplemented).
    case unavailable
  }

  let tripID: String
  private(set) var items: [Loci_Trip_ChecklistItem]
  private(set) var dismissed: [String]
  private(set) var suggestions: [Loci_Trip_PackingSuggestion] = []
  private(set) var weatherIsEstimated = false
  private(set) var availability: Availability
  var error: String?

  private let service: TripChecklistService
  private let locale: Locale

  init(
    tripID: String,
    service: TripChecklistService = ConnectTripChecklistService(),
    items: [Loci_Trip_ChecklistItem] = [],
    dismissed: [String] = [],
    suggestions: [Loci_Trip_PackingSuggestion] = [],
    availability: Availability = .loading,
    locale: Locale = .current
  ) {
    self.tripID = tripID
    self.service = service
    self.items = items
    self.dismissed = dismissed
    self.suggestions = suggestions
    self.availability = availability
    self.locale = locale
  }

  var packing: [Loci_Trip_ChecklistItem] { TripChecklist.items(items, kind: .packing) }
  var expenses: [Loci_Trip_ChecklistItem] { TripChecklist.items(items, kind: .expense) }
  var openSuggestions: [Loci_Trip_PackingSuggestion] {
    TripChecklist.openSuggestions(suggestions, items: items, dismissed: dismissed)
  }
  var packedSummary: String? { TripChecklist.packedSummary(items) }
  var currency: String { TripChecklist.defaultCurrency(items, locale: locale) }
  var totalLabel: String { TripChecklist.totalLabel(items, fallbackCurrency: currency, locale: locale) }
  var canEdit: Bool { availability == .ready }

  // MARK: - Load

  func load() async {
    async let checklist: Void = loadChecklist()
    async let packing: Void = loadSuggestions()
    _ = await (checklist, packing)
  }

  private func loadChecklist() async {
    do {
      let response = try await service.checklist(tripID: tripID)
      items = response.items
      dismissed = response.dismissedSuggestions
      availability = .ready
    } catch {
      if error.isUnimplemented {
        availability = .unavailable
      } else if !error.isCancelled {
        // Keep whatever is on screen; a failed refresh is not an empty list.
        if availability == .loading { availability = .unavailable }
        self.error = error.message
      }
    }
  }

  /// Suggestions are a nice-to-have (web retries once and moves on), so a
  /// failure leaves the panel empty rather than raising an alert.
  private func loadSuggestions() async {
    guard let response = try? await service.suggestions(tripID: tripID) else { return }
    suggestions = response.suggestions
    weatherIsEstimated = response.weatherIsEstimated
  }

  // MARK: - Edits

  func addPacking(_ text: String) async {
    guard let item = TripChecklist.makeItem(kind: .packing, text: text, position: TripChecklist.nextPosition(items, kind: .packing)) else { return }
    await upsert(item)
  }

  /// Returns false when the amount is not a number, so the form can keep its text.
  @discardableResult
  func addExpense(label: String, amount: String) async -> Bool {
    let currency = currency
    guard let minor = TripChecklist.amountMinor(from: amount, currency: currency),
      let item = TripChecklist.makeItem(
        kind: .expense,
        text: label,
        position: TripChecklist.nextPosition(items, kind: .expense),
        amountMinor: minor,
        currency: currency
      )
    else { return false }
    await upsert(item)
    return true
  }

  func accept(_ suggestion: Loci_Trip_PackingSuggestion) async {
    await addPacking(suggestion.text)
  }

  /// "Add all": every open suggestion, in order, as one optimistic batch.
  func acceptAll() async {
    var position = TripChecklist.nextPosition(items, kind: .packing)
    var batch: [Loci_Trip_ChecklistItem] = []
    for suggestion in openSuggestions {
      guard let item = TripChecklist.makeItem(kind: .packing, text: suggestion.text, position: position) else { continue }
      batch.append(item)
      position += 1
    }
    await withTaskGroup(of: Void.self) { group in
      for item in batch { group.addTask { await self.upsert(item) } }
    }
  }

  func toggle(_ item: Loci_Trip_ChecklistItem) async {
    var next = item
    next.done.toggle()
    await upsert(next)
  }

  func delete(_ item: Loci_Trip_ChecklistItem) async {
    guard canEdit, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    let removed = items.remove(at: index)
    do {
      try await service.delete(tripID: tripID, itemID: removed.id)
    } catch {
      if !items.contains(where: { $0.id == removed.id }) { items.insert(removed, at: min(index, items.count)) }
      report(error)
    }
  }

  func dismiss(_ suggestion: Loci_Trip_PackingSuggestion) async {
    guard canEdit else { return }
    let key = TripChecklist.key(suggestion.text)
    guard !key.isEmpty, !dismissed.contains(where: { TripChecklist.key($0) == key }) else { return }
    dismissed.append(key)
    do {
      try await service.dismiss(tripID: tripID, text: suggestion.text)
    } catch {
      dismissed.removeAll { $0 == key }
      report(error)
    }
  }

  /// Show the item now, adopt the server's copy on success, and on failure put
  /// back exactly what was there before (nothing, for a new item).
  private func upsert(_ item: Loci_Trip_ChecklistItem) async {
    guard canEdit else { return }
    if item.kind == .packing || item.kind == .expense,
      !items.contains(where: { $0.id == item.id }), items.count >= TripChecklist.maxItems
    {
      error = "This trip's checklist is full (\(TripChecklist.maxItems) items). Remove something first."
      return
    }
    let previous = items.first { $0.id == item.id }
    replace(item)
    do {
      let saved = try await service.upsert(tripID: tripID, item: item)
      // A later edit to the same item may already be on screen; keep it.
      if let current = items.first(where: { $0.id == item.id }), current == item { replace(saved) }
    } catch {
      if let previous { replace(previous) } else { items.removeAll { $0.id == item.id } }
      report(error)
    }
  }

  private func replace(_ item: Loci_Trip_ChecklistItem) {
    if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item } else { items.append(item) }
  }

  private func report(_ error: TripRPCError) {
    guard !error.isCancelled else { return }
    if error.code == .resourceExhausted {
      self.error = "This trip's checklist is full (\(TripChecklist.maxItems) items). Remove something first."
    } else {
      self.error = error.message
    }
  }
}
