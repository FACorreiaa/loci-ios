import SwiftUI
import UIKit

/// "Import from a link": paste a TikTok, reel, YouTube, Maps or blog link and
/// keep the places it mentions in a list.
struct ImportFromLinkSheet: View {
  let lists: [LociList]
  @State private var store: LinkImportStore
  @Environment(\.dismiss) private var dismiss

  init(lists: [LociList], store: LinkImportStore = LinkImportStore()) {
    self.lists = lists
    _store = State(initialValue: store)
  }

  var body: some View {
    NavigationStack {
      Form {
        linkSection
        if let result = store.result { placesSection(result) }
        if store.result != nil { saveSection }
      }
      .navigationTitle("Import from a link")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
      }
      .errorAlert($store.error)
    }
  }

  private var linkSection: some View {
    Section {
      TextField("https://www.tiktok.com/@…", text: $store.url)
        .keyboardType(.URL)
        .textContentType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.go)
        .onSubmit { Task { await store.read() } }
      TextField("City, if the link doesn't say", text: $store.cityHint)
        .textInputAutocapitalization(.words)
      HStack {
        Button("Paste", systemImage: "doc.on.clipboard") {
          if let text = UIPasteboard.general.string { store.url = text }
        }
        .buttonStyle(.bordered)
        Spacer()
        Button {
          Task { await store.read() }
        } label: {
          if store.isReading {
            ProgressView()
          } else {
            Text("Find places")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isReading || store.url.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    } footer: {
      Text("Saw a place on TikTok, Instagram, YouTube, Google Maps or a blog? Paste the link.")
    }
  }

  private func placesSection(_ result: LinkImportResult) -> some View {
    Section {
      ForEach(result.places) { place in
        Button {
          store.toggle(place)
        } label: {
          ImportedPlaceRow(place: place, picked: store.isPicked(place))
        }
        .buttonStyle(.plain)
        .disabled(!place.canSave)
      }
    } header: {
      Text([result.source, result.city].filter { !$0.isEmpty }.joined(separator: " · "))
    } footer: {
      if !result.title.isEmpty { Text(result.title).lineLimit(2) }
    }
  }

  private var saveSection: some View {
    Section {
      Picker("Save to", selection: $store.target) {
        Text("A new list").tag(LinkImportTarget.new)
        ForEach(lists) { list in
          Text(list.name).tag(LinkImportTarget.existing(list.id))
        }
      }
      if store.target == .new {
        TextField("List name", text: $store.listName)
      }
      Button {
        Task { await store.save() }
      } label: {
        if store.isSaving {
          ProgressView()
        } else {
          Text(store.chosen.count == 1 ? "Save 1 place" : "Save \(store.chosen.count) places")
        }
      }
      .disabled(store.isSaving || store.chosen.isEmpty)
    } footer: {
      if let outcome = store.outcome { Text(Self.summary(outcome)) }
    }
  }

  static func summary(_ outcome: LinkImportOutcome) -> String {
    var parts = ["\(outcome.added) saved"]
    if outcome.already > 0 { parts.append("\(outcome.already) already there") }
    if outcome.failed > 0 { parts.append("\(outcome.failed) didn't save, tap Save to retry") }
    return parts.joined(separator: ", ") + "."
  }
}

private struct ImportedPlaceRow: View {
  let place: ImportedPlace
  let picked: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: picked ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(picked ? Color.accentColor : .secondary)
        .opacity(place.canSave ? 1 : 0.4)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(place.name).font(.body.weight(.medium))
        Text(detail).font(.caption).foregroundStyle(.secondary)
        if !place.note.isEmpty {
          Text("\u{201C}\(place.note)\u{201D}").font(.caption).italic().foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
    .contentShape(Rectangle())
    .opacity(place.canSave ? 1 : 0.6)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(picked ? .isSelected : [])
  }

  private var detail: String {
    guard place.canSave else { return place.city.isEmpty ? "Not found on Loci" : "Not found on Loci in \(place.city)" }
    return [place.category, place.address ?? place.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
  }
}
