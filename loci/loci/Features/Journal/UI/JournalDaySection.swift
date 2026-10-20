import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// One day of the journal: the note, the plan as it went, and the photos.
struct JournalDaySection: View {
  let day: Loci_Journal_JournalDay
  let photosEnabled: Bool
  let uploading: Bool
  let onSaveDiary: (String) -> Void
  let onAddPhotos: ([Data]) -> Void
  let onDeletePhoto: (String) -> Void

  var body: some View {
    Section {
      DiaryEditor(saved: day.diary, onSave: onSaveDiary)
      ForEach(day.stops, id: \.stopID) { stop in
        JournalStopRow(stop: stop, onDeletePhoto: onDeletePhoto)
      }
      if !day.extraVisits.isEmpty {
        ForEach(day.extraVisits, id: \.poiID) { visit in
          JournalPlaceLine(
            name: visit.name.isEmpty ? "Unnamed place" : visit.name,
            visited: visit.hasVisitedAt ? visit.visitedAt.date : nil,
            verdict: visit.verdict,
            note: "Also visited",
          )
        }
      }
      JournalPhotoGrid(photos: day.photos, onDelete: onDeletePhoto)
      if photosEnabled {
        AddPhotosButton(uploading: uploading, onPick: onAddPhotos)
      }
    } header: {
      HStack {
        Text(JournalFormat.heading(day))
        Spacer()
        if let visited = JournalFormat.visited(day) { Text(visited) }
      }
    }
  }
}

/// A day's note. Saves a second after typing stops, and when the page goes away.
struct DiaryEditor: View {
  let saved: String
  let onSave: (String) -> Void
  @State private var text = ""
  @State private var loaded = false

  var body: some View {
    TextField("How did the day go?", text: $text, axis: .vertical)
      .lineLimit(3...12)
      .onAppear {
        guard !loaded else { return }
        loaded = true
        text = saved
      }
      .task(id: text) {
        guard loaded, text != saved else { return }
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        onSave(String(text.prefix(4000)))
      }
      .onDisappear {
        if loaded, text != saved { onSave(String(text.prefix(4000))) }
      }
  }
}

private struct JournalStopRow: View {
  let stop: Loci_Journal_JournalStop
  let onDeletePhoto: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      JournalPlaceLine(
        name: stop.name,
        visited: stop.hasVisitedAt ? stop.visitedAt.date : nil,
        verdict: stop.verdict,
        note: stop.notes,
        planned: true,
      )
      JournalPhotoGrid(photos: stop.photos, onDelete: onDeletePhoto)
    }
  }
}

private struct JournalPlaceLine: View {
  let name: String
  let visited: Date?
  let verdict: Loci_Ranking_Verdict
  var note = ""
  var planned = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      if planned {
        Image(systemName: visited == nil ? "circle" : "checkmark.circle.fill")
          .foregroundStyle(visited == nil ? Color.secondary : Color.accentColor)
          .accessibilityLabel(visited == nil ? "Not visited" : "Visited")
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(name).lineLimit(1)
        if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
      }
      Spacer(minLength: 8)
      if let label = JournalFormat.verdict(verdict) {
        Text(label).font(.caption2).foregroundStyle(.secondary)
          .padding(.horizontal, 8).padding(.vertical, 2)
          .overlay(Capsule().strokeBorder(.quaternary))
      }
      if let visited {
        Text(visited, style: .time).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
