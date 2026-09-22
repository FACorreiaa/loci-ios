import LociConnectProto
import SwiftUI

/// Tags (web: settings tab "tags"). TagsService: GetTags{}, CreateTag{name,
/// description, tagType, active}, UpdateTag{tagId, …}, DeleteTag{tagId}.
struct TagsSettingsView: View {
  @State private var tags: [Loci_Tags_Tag] = []
  @State private var editing: NamedItemDraft?
  @State private var error: String?

  var body: some View {
    List {
      ForEach(tags, id: \.id) { tag in
        Button {
          editing = NamedItemDraft(id: tag.id, name: tag.name, description: tag.description_p, active: tag.active, kind: tag.tagType)
        } label: {
          NamedItemRow(name: tag.name, detail: tag.description_p, active: tag.active, badge: tag.tagType)
        }
        .swipeActions { Button("Delete", role: .destructive) { Task { await delete(tag.id) } } }
      }
    }
    .overlay { if tags.isEmpty { ContentUnavailableView("No tags yet", systemImage: "tag") } }
    .settingsStyle("Tags")
    .toolbar { Button("Add", systemImage: "plus") { editing = NamedItemDraft(kind: "preference") } }
    .sheet(item: $editing) { draft in
      NamedItemEditor(title: draft.id == nil ? "New tag" : "Edit tag", draft: draft, showsKind: true) { await save($0) }
    }
    .refreshable { await load() }
    .errorAlert($error)
    .task { await load() }
  }

  private func load() async {
    do {
      tags = try await rpc("Could not load tags.") { await SettingsClients.tags.getTags(request: .init(), headers: [:]) }.tags
    } catch { self.error = error.userMessage }
  }

  private func save(_ draft: NamedItemDraft) async -> Bool {
    do {
      if let id = draft.id {
        var request = Loci_Tags_UpdateTagRequest()
        request.tagID = id
        request.name = draft.name
        request.description_p = draft.description
        request.tagType = draft.kind
        request.active = draft.active
        _ = try await rpc("Could not save the tag.", request) { await SettingsClients.tags.updateTag(request: $0, headers: [:]) }
      } else {
        var request = Loci_Tags_CreateTagRequest()
        request.name = draft.name
        request.description_p = draft.description
        request.tagType = draft.kind
        request.active = draft.active
        _ = try await rpc("Could not create the tag.", request) { await SettingsClients.tags.createTag(request: $0, headers: [:]) }
      }
      await load()
      return true
    } catch {
      self.error = error.userMessage
      return false
    }
  }

  private func delete(_ id: String) async {
    var request = Loci_Tags_DeleteTagRequest()
    request.tagID = id
    do {
      _ = try await rpc("Could not delete the tag.", request) { await SettingsClients.tags.deleteTag(request: $0, headers: [:]) }
      await load()
    } catch { self.error = error.userMessage }
  }
}

/// Interests (web: settings tab "interests"). InterestService: GetInterests{activeOnly: false},
/// CreateInterest{name, description, active}, UpdateInterest{interestId, name?, description?, active},
/// DeleteInterest{interestId}.
struct InterestsSettingsView: View {
  @State private var interests: [Loci_Interest_Interest] = []
  @State private var editing: NamedItemDraft?
  @State private var error: String?

  var body: some View {
    List {
      ForEach(interests, id: \.id) { interest in
        Button {
          editing = NamedItemDraft(id: interest.id, name: interest.name, description: interest.description_p, active: interest.active)
        } label: {
          NamedItemRow(name: interest.name, detail: interest.description_p, active: interest.active, badge: nil)
        }
        .swipeActions { Button("Delete", role: .destructive) { Task { await delete(interest.id) } } }
      }
    }
    .overlay { if interests.isEmpty { ContentUnavailableView("No interests yet", systemImage: "heart.text.square") } }
    .settingsStyle("Interests")
    .toolbar { Button("Add", systemImage: "plus") { editing = NamedItemDraft() } }
    .sheet(item: $editing) { draft in
      NamedItemEditor(title: draft.id == nil ? "New interest" : "Edit interest", draft: draft, showsKind: false) { await save($0) }
    }
    .refreshable { await load() }
    .errorAlert($error)
    .task { await load() }
  }

  private func load() async {
    var request = Loci_Interest_GetInterestsRequest()
    request.activeOnly = false
    do {
      interests = try await rpc("Could not load interests.", request) {
        await SettingsClients.interests.getInterests(request: $0, headers: [:])
      }.interests
    } catch { self.error = error.userMessage }
  }

  private func save(_ draft: NamedItemDraft) async -> Bool {
    do {
      if let id = draft.id {
        var request = Loci_Interest_UpdateInterestRequest()
        request.interestID = id
        if !draft.name.isEmpty { request.name = draft.name }
        if !draft.description.isEmpty { request.description_p = draft.description }
        request.active = draft.active
        _ = try await rpc("Could not save the interest.", request) { await SettingsClients.interests.updateInterest(request: $0, headers: [:]) }
      } else {
        var request = Loci_Interest_CreateInterestRequest()
        request.name = draft.name
        request.description_p = draft.description
        request.active = draft.active
        _ = try await rpc("Could not create the interest.", request) {
          await SettingsClients.interests.createInterest(request: $0, headers: [:])
        }
      }
      await load()
      return true
    } catch {
      self.error = error.userMessage
      return false
    }
  }

  private func delete(_ id: String) async {
    var request = Loci_Interest_DeleteInterestRequest()
    request.interestID = id
    do {
      _ = try await rpc("Could not delete the interest.", request) { await SettingsClients.interests.deleteInterest(request: $0, headers: [:]) }
      await load()
    } catch { self.error = error.userMessage }
  }
}

/// Form state shared by the tag and interest editors.
/// A nil `id` is a new item; the sheet treats every new draft as the same one.
struct NamedItemDraft: Identifiable, Equatable {
  var id: String?
  var name = ""
  var description = ""
  var active = true
  var kind = ""
}

struct NamedItemRow: View {
  let name: String
  let detail: String
  let active: Bool
  let badge: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(name).foregroundStyle(active ? Color.lociInk : Color.lociMutedInk)
        if let badge, !badge.isEmpty { Text(badge).lociCoordStyle(10) }
        if !active { Text("Off").lociCoordStyle(10) }
      }
      if !detail.isEmpty { Text(detail).font(.lociCaption()).foregroundStyle(Color.lociMutedInk).lineLimit(2) }
    }
  }
}

struct NamedItemEditor: View {
  let title: String
  @State var draft: NamedItemDraft
  let showsKind: Bool
  let onSave: (NamedItemDraft) async -> Bool

  @Environment(\.dismiss) private var dismiss
  @State private var isSaving = false

  /// Web requires a type for tags as well as a name (Settings/Tags.tsx).
  private var isComplete: Bool {
    !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && (!showsKind || !draft.kind.trimmingCharacters(in: .whitespaces).isEmpty)
  }

  init(title: String, draft: NamedItemDraft, showsKind: Bool, onSave: @escaping (NamedItemDraft) async -> Bool) {
    self.title = title
    self._draft = State(initialValue: draft)
    self.showsKind = showsKind
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Name", text: $draft.name)
        TextField("Description", text: $draft.description, axis: .vertical).lineLimit(2...4)
        if showsKind { TextField("Type (e.g. preference, vibe)", text: $draft.kind).textInputAutocapitalization(.never) }
        Toggle("Active", isOn: $draft.active)
      }
      .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            isSaving = true
            Task {
              if await onSave(draft) { dismiss() }
              isSaving = false
            }
          }.disabled(!isComplete || isSaving)
        }
      }
    }
    .presentationDetents([.medium])
  }
}
