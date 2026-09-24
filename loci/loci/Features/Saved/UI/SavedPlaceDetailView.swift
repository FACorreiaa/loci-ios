import LociConnectProto
import SwiftUI

/// A saved hotel, restaurant or place, pushed from Saved. It opens on what the
/// favourite kept and fills in from the server when there is more; a place the
/// server knows nothing about still opens, with its name, pin and note.
struct SavedPlaceDetailView: View {
  let item: Loci_Favorites_V1_FavoriteItem
  var onSavedChange: ((Bool) -> Void)?

  @State private var stop: Loci_Poi_POIDetailedInfo
  @State private var enriching = true

  init(item: Loci_Favorites_V1_FavoriteItem, onSavedChange: ((Bool) -> Void)? = nil) {
    self.item = item
    self.onSavedChange = onSavedChange
    _stop = State(initialValue: SavedPlace.snapshot(item))
  }

  var body: some View {
    PlaceDetailView(
      stop: stop,
      destination: SavedPlace.destination(for: item.contentType),
      cityName: item.cityName,
      savedItem: item,
      onSavedChange: onSavedChange
    )
    .navigationTitle(SavedPlace.kindLabel(item.contentType))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if enriching {
        ToolbarItem(placement: .topBarTrailing) {
          ProgressView().accessibilityLabel("Loading more details")
        }
      }
    }
    .task(id: item.id) {
      if let richer = await SavedPlaceAPI.enrich(item, base: SavedPlace.snapshot(item)) {
        withAnimation(.smooth) { stop = richer }
      }
      enriching = false
    }
  }
}

#Preview("Name-keyed place, no server detail") {
  NavigationStack { SavedPlaceDetailView(item: .savedPlaceSample) }
}
