import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

/// Pass 3, Phase 5 (the part the server has): editing an item's note, day and
/// time on a list through ListService.UpdateListItem. The proto has no field
/// presence, so only what changed is sent and a cleared note cannot be sent.
struct ListItemEditTests {
  private let listID = "9b1f0c2e-0000-4000-8000-000000000001"
  private let noon = Date(timeIntervalSince1970: 1_700_000_000)

  private func entry() -> ListEntry {
    var stop = Loci_Poi_POIDetailedInfo()
    stop.id = "5c7e0000-0000-4000-8000-000000000001"
    stop.name = "Miradouro da Graça"
    return ListEntry(itemID: "item-1", contentType: .poi, notes: "Go at dusk", dayNumber: 2, timeSlot: noon, stop: stop)
  }

  @Test func entryCarriesDayAndTimeFromTheWire() {
    var item = Loci_List_ListItem()
    item.itemID = "i"
    item.notes = "n"
    item.dayNumber = 3
    item.timeSlot = Google_Protobuf_Timestamp(date: noon)
    let mapped = ListEntry(item)
    #expect(mapped.dayNumber == 3)
    #expect(mapped.timeSlot == noon)
    item.dayNumber = 0
    item.clearTimeSlot()
    #expect(ListEntry(item).dayNumber == nil)
    #expect(ListEntry(item).timeSlot == nil)
  }

  @Test func editStartsFromTheEntryAndKnowsWhenItChanged() {
    let e = entry()
    var edit = ListItemEdit(e)
    #expect(edit.notes == "Go at dusk")
    #expect(edit.dayNumber == 2)
    #expect(edit.timeSlot == noon)
    #expect(!edit.isChanged(from: e))
    edit.notes = "Go at dusk "
    #expect(!edit.isChanged(from: e), "whitespace is not a change")
    edit.dayNumber = 3
    #expect(edit.isChanged(from: e))
  }

  @Test func requestSendsOnlyWhatChanged() {
    let e = entry()
    var edit = ListItemEdit(e)
    edit.dayNumber = 3
    let request = ListPayload.updateItem(userId: "u", listId: listID, entry: e, edit: edit)
    #expect(request?.listID == listID)
    #expect(request?.itemID == "item-1")
    #expect(request?.contentType == .poi)
    #expect(request?.dayNumber == 3)
    #expect(request?.notes.isEmpty == true, "unchanged note is left alone")
    #expect(request?.hasTimeSlot == false)
    #expect(ListPayload.updateItem(userId: "u", listId: listID, entry: e, edit: ListItemEdit(e)) == nil, "nothing changed, nothing sent")
  }

  @Test func notesAreTrimmedAndCappedAndCannotBeCleared() {
    let e = entry()
    var edit = ListItemEdit(e)
    edit.notes = "  " + String(repeating: "x", count: ListItemEdit.maxNotes + 5)
    let request = ListPayload.updateItem(userId: "u", listId: listID, entry: e, edit: edit)
    #expect(request?.notes.count == ListItemEdit.maxNotes)
    edit.notes = ""
    #expect(ListItemEdit.problem(edit, from: e) == "A note can be changed but not removed yet.")
    #expect(ListPayload.updateItem(userId: "u", listId: listID, entry: e, edit: edit) == nil)
  }

  @Test func timeSlotChangeIsSentAndAClearedDayIsRefused() {
    let e = entry()
    var edit = ListItemEdit(e)
    edit.timeSlot = noon.addingTimeInterval(3600)
    let request = ListPayload.updateItem(userId: "u", listId: listID, entry: e, edit: edit)
    #expect(request?.hasTimeSlot == true)
    #expect(request?.timeSlot.date == noon.addingTimeInterval(3600))
    #expect(request?.dayNumber == 0, "unchanged day is not sent")

    edit.dayNumber = nil
    #expect(ListItemEdit.problem(edit, from: e) == "A day can be changed but not removed yet.")
    #expect(ListPayload.updateItem(userId: "u", listId: listID, entry: e, edit: edit) == nil, "no presence on the wire, so it cannot be sent")
  }

  @Test func appliedEditUpdatesTheEntryInPlace() {
    let e = entry()
    var edit = ListItemEdit(e)
    edit.notes = "Sunrise instead"
    edit.dayNumber = 1
    let applied = edit.applied(to: e)
    #expect(applied.notes == "Sunrise instead")
    #expect(applied.dayNumber == 1)
    #expect(applied.stop == e.stop)
    #expect(applied.itemID == e.itemID)
  }
}
