import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Places I've been: the diary side of the globe. The globe shows cities;
/// this shows the places, each one a signal the taste profile learned from.
struct VisitedPlacesView: View {
  @State private var store: VisitedPlacesStore

  init(store: VisitedPlacesStore = VisitedPlacesStore()) { _store = State(initialValue: store) }

  var body: some View {
    content
      .navigationTitle("Places I've been")
      .navigationBarTitleDisplayMode(.inline)
      .task { if store.phase == .idle { await store.load() } }
      .refreshable { await store.load() }
      .alert("Couldn't remove that place", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(store.error ?? "")
      }
  }

  @ViewBuilder private var content: some View {
    switch store.phase {
    case .idle, .loading:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      ContentUnavailableView {
        Label("Couldn't load your places", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { Task { await store.load() } }
      }
    case .loaded where store.visits.isEmpty:
      ContentUnavailableView(
        "No places yet",
        systemImage: "figure.walk",
        description: Text("Places you visit or mark as been-there show up here. Open any place and tap \u{201C}I've been here\u{201D}."),
      )
    case .loaded:
      list
    }
  }

  private var list: some View {
    List {
      ForEach(store.grouped) { group in
        Section("\(group.city) · \(group.places.count)") {
          ForEach(group.places, id: \.id) { visit in
            VisitedPlaceRow(visit: visit)
              .swipeActions {
                Button("Remove", systemImage: "trash", role: .destructive) { Task { await store.delete(visit.id) } }
              }
          }
        }
      }
      if store.canLoadMore {
        ProgressView().frame(maxWidth: .infinity).task { await store.loadMore() }
      }
    }
    .listStyle(.insetGrouped)
  }
}

private struct VisitedPlaceRow: View {
  let visit: Loci_Travelhistory_VisitedPOI

  private var sourceLabel: String? {
    switch visit.source {
    case .visitEvent: "Walked"
    case .manual: "Added"
    case .trip: "From a trip"
    case .backfill: "From history"
    default: nil
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      Text(visit.poiName.isEmpty ? "Unnamed place" : visit.poiName).lineLimit(1)
      Spacer(minLength: 8)
      if let sourceLabel {
        Text(sourceLabel).font(.caption2).foregroundStyle(.secondary)
          .padding(.horizontal, 8).padding(.vertical, 2)
          .overlay(Capsule().strokeBorder(.quaternary))
      }
      if visit.hasVisitedAt {
        Text(visit.visitedAt.date, format: .dateTime.day().month(.abbreviated).year())
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  NavigationStack { VisitedPlacesView() }
}
