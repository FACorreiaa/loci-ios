import SwiftUI

/// Lists (web: /lists), from Profile › Lists. Saved's Lists segment shows the
/// same rows and chrome inside its own list (`ListsRows` + `.listsChrome`).
struct ListsView: View {
  @State var store: ListsStore

  init(store: ListsStore = ListsStore()) {
    _store = State(initialValue: store)
  }

  var body: some View {
    List {
      ListsRows(store: store)
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Color.lociPaper.ignoresSafeArea())
    .listsChrome(store: store)
    .refreshable { await store.load() }
    .navigationTitle("Lists")
    .onAppear { Analytics.screen("lists") }
  }
}

/// The tab chips and one row per list, for any `List`.
struct ListsRows: View {
  @Bindable var store: ListsStore

  var body: some View {
    switch store.phase {
    case .idle, .loading: ListsSkeleton()
    case .failed: EmptyView()
    case .loaded:
      if !store.lists.isEmpty {
        ListsTabChips(selection: $store.tab, counts: ListFilter.counts(store.lists))
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
      }
      ForEach(store.visible) { list in
        NavigationLink(value: list) { ListRow(list: list) }
          .listRowBackground(Color.lociCard)
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive) { store.pendingDelete = list }
            Button("Edit", systemImage: "pencil") { store.editor = .edit(list) }.tint(Color.lociForestFill)
          }
          .contextMenu {
            Button("Edit", systemImage: "pencil") { store.editor = .edit(list) }
            Button("Delete", systemImage: "trash", role: .destructive) { store.pendingDelete = list }
          }
      }
    }
  }
}

extension View {
  /// Loading, empty and error states, the New list button, the create/edit
  /// sheet, the delete confirmation, the free-limit sheet and the push to a list.
  /// `isActive` false (another Saved segment) leaves only the destination.
  func listsChrome(store: ListsStore, isActive: Bool = true) -> some View {
    modifier(ListsChrome(store: store, isActive: isActive))
  }
}

private struct ListsChrome: ViewModifier {
  @Bindable var store: ListsStore
  let isActive: Bool

  func body(content: Content) -> some View {
    content
      .overlay { if isActive { overlay } }
      .toolbar {
        if isActive {
          ToolbarItem(placement: .primaryAction) {
            Button("New list", systemImage: "plus") { store.editor = .new }
          }
        }
      }
      .navigationDestination(for: LociList.self) { list in
        ListDetailView(store: ListDetailStore(listID: list.id, initial: list, service: store.service))
      }
      .sheet(item: $store.editor) { editor in
        ListFormSheet(editor: editor) { form in await store.save(form, editing: editor.list) }
      }
      .sheet(item: $store.limit) { EntitlementSheet(limit: $0) }
      .confirmationDialog(
        "Delete \u{201C}\(store.pendingDelete?.name ?? "")\u{201D}?",
        isPresented: Binding(get: { store.pendingDelete != nil }, set: { if !$0 { store.pendingDelete = nil } }),
        titleVisibility: .visible,
        presenting: store.pendingDelete
      ) { list in
        Button("Delete", role: .destructive) { Task { await store.delete(list) } }
      } message: { _ in
        Text("This can't be undone.")
      }
      .errorAlert($store.error)
      .task { if isActive { await store.loadIfNeeded() } }
      .onChange(of: isActive) { if isActive { Task { await store.loadIfNeeded() } } }
  }

  @ViewBuilder private var overlay: some View {
    switch store.phase {
    case .failed(let message):
      ContentUnavailableView {
        Label("Could not load your lists", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { Task { await store.load() } }.lociProminentButton()
      }
    case .loaded where store.visible.isEmpty:
      // Web's copy, per tab.
      ContentUnavailableView {
        Label(store.tab.emptyTitle, systemImage: "folder.badge.plus")
      } description: {
        Text("Create your first list to start organizing your favorite places and travel plans.")
      } actions: {
        Button("Create a list", systemImage: "plus") { store.editor = .new }
          .lociProminentButton()
      }
    default: EmptyView()
    }
  }
}

/// Name with its public/private mark, the Itinerary badge, the description and the date.
struct ListRow: View {
  let list: LociList

  @Environment(\.dynamicTypeSize) private var typeSize

  private var meta: String {
    var parts: [String] = []
    if list.isItinerary { parts.append("Itinerary") }
    if list.itemCount > 0 { parts.append(list.itemCount == 1 ? "1 place" : "\(list.itemCount) places") }
    if let created = list.createdAt { parts.append(created.formatted(.dateTime.month(.abbreviated).day())) }
    return parts.joined(separator: " · ")
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: list.isItinerary ? "map" : "list.bullet.rectangle")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color.lociForest)
        .frame(width: 32, height: 32)
        .background(Color.lociMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(list.name).font(.lociHeadline(16)).foregroundStyle(Color.lociInk).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
          Image(systemName: list.isPublic ? "globe" : "lock")
            .font(.caption)
            .foregroundStyle(list.isPublic ? Color.lociForest : Color.lociMutedInk)
            .accessibilityLabel(list.isPublic ? "Public" : "Private")
        }
        if !list.description.isEmpty {
          Text(list.description).font(.lociCaption()).foregroundStyle(Color.lociMutedInk).lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
        }
        if !meta.isEmpty { Text(meta).lociCoordStyle(10) }
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}

/// All / Custom / Itineraries with their counts (web's tab bar).
private struct ListsTabChips: View {
  @Binding var selection: ListsTab
  let counts: [ListsTab: Int]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(ListsTab.allCases) { tab in
          let isOn = selection == tab
          Button {
            selection = tab
          } label: {
            HStack(spacing: 5) {
              Text(tab.title)
              Text("\(counts[tab] ?? 0)").monospacedDigit().opacity(0.7)
            }
            .font(.lociCaption(13))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOn ? Color.lociForest : Color.lociMuted, in: Capsule())
            .foregroundStyle(isOn ? Color.lociPaper : Color.lociInk)
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(isOn ? .isSelected : [])
        }
      }
      .padding(.horizontal, 4)
      .padding(.vertical, 4)
    }
    .accessibilityLabel("Filter lists")
  }
}

private struct ListsSkeleton: View {
  var body: some View {
    Section {
      ForEach(0..<4, id: \.self) { _ in
        ListRow(list: LociList(id: "", name: "Weekend in Porto", description: "Places to try next time"))
          .redacted(reason: .placeholder)
      }
    }
    .listRowBackground(Color.lociCard)
    .accessibilityLabel("Loading")
  }
}

/// Create or edit (web: the ListsPage modal): Name is required. The kind is
/// locked on edit, because UpdateList has no field for it.
struct ListFormSheet: View {
  let editor: ListEditor
  let onSave: (ListForm) async -> Bool

  @Environment(\.dismiss) private var dismiss
  @State private var form: ListForm
  @State private var saving = false
  @FocusState private var nameFocused: Bool

  init(editor: ListEditor, onSave: @escaping (ListForm) async -> Bool) {
    self.editor = editor
    self.onSave = onSave
    _form = State(initialValue: editor.list.map(ListForm.init) ?? ListForm())
  }

  private var isEditing: Bool { editor.list != nil }

  var body: some View {
    NavigationStack {
      Form {
        Section("Name") {
          TextField("My travel list", text: $form.name).focused($nameFocused).submitLabel(.done)
        }
        Section("Description") {
          TextField("Optional description…", text: $form.description, axis: .vertical).lineLimit(3...6)
        }
        Section {
          Toggle("This is an itinerary", isOn: $form.isItinerary).disabled(isEditing)
          Toggle("Make public", isOn: $form.isPublic)
        } footer: {
          if isEditing { Text("Whether it is an itinerary is set when the list is created.") }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle(isEditing ? "Edit list" : "New list")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          } else {
            Button(isEditing ? "Save" : "Create") { Task { await save() } }.disabled(!form.isValid)
          }
        }
      }
      .onAppear { if !isEditing { nameFocused = true } }
    }
    .adaptiveDetents([.medium, .large])
    .interactiveDismissDisabled(saving)
  }

  private func save() async {
    saving = true
    let done = await onSave(form)
    saving = false
    if done { dismiss() }
  }
}

/// The free-plan limit, in neutral words and with no way to buy (App Store 3.1.1).
struct EntitlementSheet: View {
  let limit: EntitlementLimit

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "sparkles")
        .font(.system(size: 30, weight: .medium))
        .foregroundStyle(Color.lociForest)
        .frame(width: 64, height: 64)
        .background(Color.lociMuted, in: Circle())
        .accessibilityHidden(true)
      Text(limit.title).font(.lociTitle(22)).foregroundStyle(Color.lociInk).multilineTextAlignment(.center)
      Text(limit.message).font(.lociBody(16)).foregroundStyle(Color.lociInk).multilineTextAlignment(.center)
      Text(limit.suggestion).font(.lociCaption(14)).foregroundStyle(Color.lociMutedInk).multilineTextAlignment(.center)
      Button("OK") { dismiss() }
        .lociProminentButton()
        .controlSize(.large)
        .padding(.top, 6)
    }
    .padding(24)
    .frame(maxWidth: .infinity)
    .background(Color.lociPaper.ignoresSafeArea())
    .adaptiveDetents([.height(340), .medium])
    .presentationDragIndicator(.visible)
  }
}
