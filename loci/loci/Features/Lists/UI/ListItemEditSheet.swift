import LociConnectProto
import SwiftUI

/// Note, day and time on one list item (ListService.UpdateListItem). What the
/// server cannot take back — a cleared note or day — is said in the sheet
/// rather than silently kept.
struct ListItemEditSheet: View {
  let entry: ListEntry
  let onSave: (ListItemEdit) async -> Bool

  @Environment(\.dismiss) private var dismiss
  @State private var edit: ListItemEdit
  @State private var hasDay: Bool
  @State private var hasTime: Bool
  @State private var isSaving = false

  init(entry: ListEntry, onSave: @escaping (ListItemEdit) async -> Bool) {
    self.entry = entry
    self.onSave = onSave
    let initial = ListItemEdit(entry)
    _edit = State(initialValue: initial)
    _hasDay = State(initialValue: initial.dayNumber != nil)
    _hasTime = State(initialValue: initial.timeSlot != nil)
  }

  private var problem: String? { ListItemEdit.problem(edit, from: entry) }
  private var canSave: Bool { edit.isChanged(from: entry) && problem == nil && !isSaving }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Why this place, or what to do there", text: $edit.notes, axis: .vertical).lineLimit(3...8)
          Text("\(edit.trimmedNotes.count)/\(ListItemEdit.maxNotes)").lociCoordStyle(10)
        } header: {
          Text("Note")
        }
        Section("When") {
          Toggle("On a day", isOn: $hasDay)
            .onChange(of: hasDay) { _, on in edit.dayNumber = on ? (edit.dayNumber ?? entry.dayNumber ?? 1) : nil }
          if hasDay {
            Stepper("Day \(edit.dayNumber ?? 1)", value: Binding(get: { edit.dayNumber ?? 1 }, set: { edit.dayNumber = $0 }), in: 1...30)
          }
          Toggle("At a time", isOn: $hasTime)
            .onChange(of: hasTime) { _, on in edit.timeSlot = on ? (edit.timeSlot ?? entry.timeSlot ?? Date()) : nil }
          if hasTime {
            DatePicker(
              "Time",
              selection: Binding(get: { edit.timeSlot ?? Date() }, set: { edit.timeSlot = $0 }),
              displayedComponents: .hourAndMinute
            )
          }
        }
        if let problem {
          Section { Text(problem).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk) }
        }
      }
      .navigationTitle(entry.stop.name.isEmpty ? "This place" : entry.stop.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(isSaving ? "Saving…" : "Save") { Task { await save() } }.disabled(!canSave)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func save() async {
    isSaving = true
    defer { isSaving = false }
    if await onSave(edit) { dismiss() }
  }
}

/// The note and schedule under a list item's card; tapping opens the sheet.
struct ListEntryNote: View {
  let entry: ListEntry
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: 2) {
        if let line = entry.scheduleLine() { Text(line).lociCoordStyle(10) }
        if !entry.notes.isEmpty {
          Text(entry.notes).font(.lociCaption(13)).foregroundStyle(Color.lociInk).multilineTextAlignment(.leading).lineLimit(3)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityHint("Edits the note, day or time")
  }
}
