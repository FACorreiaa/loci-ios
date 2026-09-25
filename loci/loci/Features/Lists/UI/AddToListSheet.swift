import LociConnectProto
import SwiftUI

/// Add a place to one of your lists, or to a new one (web: AddToListButton's
/// modal). Closes once the place is in; a free-plan refusal opens the limit sheet.
struct AddToListSheet: View {
  @State var store: AddToListStore
  @State private var newName = ""
  @State private var added = false
  @FocusState private var nameFocused: Bool
  @Environment(\.dismiss) private var dismiss

  init(store: AddToListStore) {
    _store = State(initialValue: store)
  }

  init(stop: Loci_Poi_POIDetailedInfo, destination: SearchDestination) {
    self.init(store: AddToListStore(stop: stop, destination: destination))
  }

  private var canCreate: Bool { !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isCreating }

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 8) {
            TextField("New list name", text: $newName)
              .focused($nameFocused)
              .submitLabel(.done)
              .onSubmit { if canCreate { Task { await create() } } }
            if store.isCreating {
              ProgressView()
            } else {
              Button("Create", systemImage: "plus.circle.fill") { Task { await create() } }
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(canCreate ? Color.lociForest : Color.lociMutedInk)
                .disabled(!canCreate)
                .buttonStyle(.plain)
            }
          }
        } header: {
          Text("New list")
        } footer: {
          Text("Creates the list and puts \(store.placeName) in it.")
        }
        .listRowBackground(Color.lociCard)

        lists
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle("Add to list")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
      .errorAlert($store.error)
      .sheet(item: $store.limit) { EntitlementSheet(limit: $0) }
      .task { await store.load() }
      .sensoryFeedback(.success, trigger: added)
      .onAppear { Analytics.screen("add_to_list") }
    }
    .adaptiveDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder private var lists: some View {
    switch store.phase {
    case .loading:
      Section("Your lists") { ProgressView().frame(maxWidth: .infinity) }.listRowBackground(Color.lociCard)
    case .failed(let message):
      Section("Your lists") {
        VStack(alignment: .leading, spacing: 8) {
          Text(message).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          Button("Try again") { Task { await store.load() } }
        }
      }
      .listRowBackground(Color.lociCard)
    case .loaded:
      Section("Your lists") {
        if store.lists.isEmpty {
          Text("No lists yet. Name one above to start.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        }
        ForEach(store.lists) { list in
          Button {
            Task { await add(to: list) }
          } label: {
            HStack {
              ListRow(list: list)
              Spacer(minLength: 8)
              if store.busyID == list.id {
                ProgressView()
              } else {
                Image(systemName: "plus").foregroundStyle(Color.lociForest).accessibilityHidden(true)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(store.busyID != nil || store.isCreating)
          .accessibilityHint("Adds \(store.placeName) to this list")
        }
      }
      .listRowBackground(Color.lociCard)
    }
  }

  private func add(to list: LociList) async {
    if await store.add(to: list) { finish() }
  }

  private func create() async {
    nameFocused = false
    if await store.createAndAdd(name: newName) {
      newName = ""
      finish()
    }
  }

  private func finish() {
    added.toggle()
    dismiss()
  }
}
