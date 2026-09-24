import LociConnectProto
import SwiftUI

/// One list (web has no page here: `/lists/:id` 404s). Its places as stop
/// cards, a map when any of them has a position, tap for the place, swipe to
/// take one out.
struct ListDetailView: View {
  @State var store: ListDetailStore
  @State private var opened: ListEntry?
  @State private var selectedID: String?
  @State private var showFullMap = false

  init(store: ListDetailStore) {
    _store = State(initialValue: store)
  }

  /// For an app link, which carries only the id.
  init(listID: String) {
    self.init(store: ListDetailStore(listID: listID))
  }

  private var entries: [ListEntry] { store.detail?.entries ?? [] }
  private var group: [DayGroup] { [DayGroup(number: 1, stops: entries.map(\.stop))] }
  private var sequence: [String: Int] { DayGrouping.sequence(group) }
  private var mapData: ResultsMapData {
    ResultsMapData(groups: group, extras: [], sequence: sequence, showsDays: false, alerts: [])
  }
  private var title: String { store.detail?.list.name ?? "List" }

  var body: some View {
    List {
      if let list = store.detail?.list { header(list) }
      if !mapData.isEmpty {
        ResultsMapCard(data: mapData, selectedID: selectedID) { showFullMap = true }
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
      }
      if store.phase == .loaded {
        ForEach(entries) { entry in
          StopCard(
            stop: entry.stop,
            index: sequence[entry.stop.stableID] ?? 0,
            color: LociTheme.listColor,
            destination: entry.destination,
            isSelected: selectedID == entry.stop.stableID
          ) {
            selectedID = entry.stop.stableID
            opened = entry
          }
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Remove", systemImage: "minus.circle", role: .destructive) { Task { await store.remove(entry) } }
          }
        }
        let unplaced = entries.count - mapData.pins.count
        if !mapData.isEmpty, unplaced > 0 {
          Text(unplaced == 1 ? "1 place has no position on the map." : "\(unplaced) places have no position on the map.")
            .font(.lociCaption())
            .foregroundStyle(Color.lociMutedInk)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
      } else if store.phase == .loading {
        ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear).listRowSeparator(.hidden)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .contentMargins(.horizontal, LociTheme.defaultPadding, for: .scrollContent)
    .background(Color.lociPaper.ignoresSafeArea())
    .overlay { overlay }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(item: $opened) { entry in
      PlaceDetailView(stop: entry.stop, destination: entry.destination, cityName: entry.stop.city)
        .navigationTitle(entry.stop.name)
        .navigationBarTitleDisplayMode(.inline)
    }
    .fullScreenCover(isPresented: $showFullMap) {
      FullMapView(
        data: mapData,
        groups: group,
        sequence: sequence,
        destination: .activities,
        showsDays: false,
        title: title,
        selectedID: $selectedID
      )
    }
    .refreshable { await store.load() }
    .task { await store.load() }
    .errorAlert($store.error)
    .onAppear { Analytics.screen("list_detail") }
  }

  private func headerMeta(_ list: LociList) -> String {
    var parts = [list.isPublic ? "Public" : "Private"]
    if list.isItinerary { parts.append("Itinerary") }
    if store.phase == .loaded { parts.append(entries.count == 1 ? "1 place" : "\(entries.count) places") }
    return parts.joined(separator: " · ")
  }

  private func header(_ list: LociList) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: list.isPublic ? "globe" : "lock").accessibilityHidden(true)
        Text(headerMeta(list))
      }
      .lociCoordStyle(10)
      Text(list.name).font(.lociTitle(24)).foregroundStyle(Color.lociInk)
      if !list.description.isEmpty {
        Text(list.description).font(.lociBody(15)).foregroundStyle(Color.lociMutedInk)
      }
    }
    .padding(.vertical, 6)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var overlay: some View {
    switch store.phase {
    case .failed(let message):
      ContentUnavailableView {
        Label("Could not load this list", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { Task { await store.load() } }.buttonStyle(.borderedProminent).tint(Color.lociForest)
      }
    case .loaded where entries.isEmpty:
      ContentUnavailableView(
        "Nothing in this list yet",
        systemImage: "list.bullet.rectangle",
        description: Text("Open a place from any result and tap Add to list.")
      )
    default: EmptyView()
    }
  }
}
