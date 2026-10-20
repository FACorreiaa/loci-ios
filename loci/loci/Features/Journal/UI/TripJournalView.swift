import LociConnectProto
import PhotosUI
import SwiftUI

/// The trip journal: each day as it went, with the traveller's own note and
/// photos. Web: /journal/trip/:id.
struct TripJournalView: View {
  @State private var store: JournalStore

  init(tripID: String, service: any JournalService = ConnectJournalService()) {
    _store = State(initialValue: JournalStore(tripID: tripID, service: service))
  }

  var body: some View {
    content
      .navigationTitle(store.journal?.title.isEmpty == false ? store.journal?.title ?? "Journal" : "Journal")
      .navigationBarTitleDisplayMode(.inline)
      .task { if store.phase == .loading { await store.load() } }
      .refreshable { await store.load() }
      .alert("Something went wrong", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(store.error ?? "")
      }
  }

  @ViewBuilder private var content: some View {
    switch store.phase {
    case .loading:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      ContentUnavailableView {
        Label("No journal for this trip", systemImage: "book.closed")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { Task { await store.load() } }
      }
    case .ready:
      if let journal = store.journal, !journal.days.isEmpty {
        list(journal)
      } else {
        ContentUnavailableView(
          "No days yet",
          systemImage: "calendar",
          description: Text("Plan a day on this trip and it shows up here."),
        )
      }
    }
  }

  private func list(_ journal: Loci_Journal_TripJournal) -> some View {
    List {
      if !store.pendingVisits.isEmpty {
        Section("Were you here?") {
          ForEach(store.pendingVisits) { visit in
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text(visit.place.name).lineLimit(1)
                Text(visit.arrival, format: .dateTime.weekday().hour().minute()).font(.caption).foregroundStyle(.secondary)
              }
              Spacer(minLength: 8)
              Button("No") { store.dismissVisit(id: visit.id) }.buttonStyle(.bordered)
              Button("Yes") { Task { await store.confirmVisit(id: visit.id) } }.buttonStyle(.borderedProminent)
            }
          }
        }
      }
      ForEach(journal.days, id: \.dayID) { day in
        JournalDaySection(
          day: day,
          photosEnabled: store.photosEnabled,
          uploading: store.uploading.contains(day.dayID),
          onSaveDiary: { text in Task { await store.saveDiary(dayID: day.dayID, text: text) } },
          onAddPhotos: { photos in Task { await store.addPhotos(photos, dayID: day.dayID) } },
          onDeletePhoto: { id in Task { await store.deletePhoto(id: id) } },
        )
      }
      if store.photosEnabled || !journal.photos.isEmpty {
        Section("From the trip") {
          JournalPhotoGrid(photos: journal.photos) { id in Task { await store.deletePhoto(id: id) } }
          if store.photosEnabled {
            AddPhotosButton(uploading: store.uploading.contains(JournalStore.tripKey)) { photos in
              Task { await store.addPhotos(photos) }
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
  }
}

/// A "Add photos" picker that hands back the picked images' data.
struct AddPhotosButton: View {
  let uploading: Bool
  let onPick: ([Data]) -> Void
  @State private var items: [PhotosPickerItem] = []

  var body: some View {
    PhotosPicker(selection: $items, maxSelectionCount: 10, matching: .images) {
      HStack(spacing: 6) {
        if uploading { ProgressView().controlSize(.small) } else { Image(systemName: "photo.badge.plus") }
        Text(uploading ? "Adding…" : "Add photos")
      }
    }
    .disabled(uploading)
    .onChange(of: items) { _, picked in
      guard !picked.isEmpty else { return }
      items = []
      Task {
        var photos: [Data] = []
        for item in picked {
          if let data = try? await item.loadTransferable(type: Data.self) { photos.append(data) }
        }
        onPick(photos)
      }
    }
  }
}

/// Photos in a wrapping grid; long-press to remove one.
struct JournalPhotoGrid: View {
  let photos: [Loci_Journal_TripPhoto]
  let onDelete: (String) -> Void

  var body: some View {
    if !photos.isEmpty {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
        ForEach(photos, id: \.id) { photo in
          AsyncImage(url: URL(string: photo.url)) { image in
            image.resizable().scaledToFill()
          } placeholder: {
            Color.secondary.opacity(0.15)
          }
          .frame(minWidth: 96, minHeight: 96)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .accessibilityLabel(photo.caption.isEmpty ? "Trip photo" : photo.caption)
          .contextMenu {
            Button("Remove photo", systemImage: "trash", role: .destructive) { onDelete(photo.id) }
          }
        }
      }
      .padding(.vertical, 4)
    }
  }
}
