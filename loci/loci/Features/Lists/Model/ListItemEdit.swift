import Foundation
import LociConnectProto

/// What the item sheet edits: the note, the day and the time slot (web has no
/// item editing; this is the part of pass 3 Phase 5 the server supports).
/// UpdateListItem has no field presence, so a cleared note or day cannot be
/// sent — the sheet says so instead of silently keeping the old value.
nonisolated struct ListItemEdit: Equatable, Sendable {
  static let maxNotes = 1000

  var notes: String
  var dayNumber: Int?
  var timeSlot: Date?

  init(_ entry: ListEntry) {
    notes = entry.notes
    dayNumber = entry.dayNumber
    timeSlot = entry.timeSlot
  }

  var trimmedNotes: String { String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNotes)) }

  func isChanged(from entry: ListEntry) -> Bool {
    trimmedNotes != entry.notes || dayNumber != entry.dayNumber || timeSlot != entry.timeSlot
  }

  /// Why Save is refused, or nil when the edit can be sent.
  static func problem(_ edit: ListItemEdit, from entry: ListEntry) -> String? {
    if edit.trimmedNotes.isEmpty, !entry.notes.isEmpty { return "A note can be changed but not removed yet." }
    if edit.dayNumber == nil, entry.dayNumber != nil { return "A day can be changed but not removed yet." }
    return nil
  }

  /// The entry as it will read once the server agrees.
  func applied(to entry: ListEntry) -> ListEntry {
    var updated = entry
    if !trimmedNotes.isEmpty { updated.notes = trimmedNotes }
    if let dayNumber { updated.dayNumber = dayNumber }
    if let timeSlot { updated.timeSlot = timeSlot }
    return updated
  }
}
