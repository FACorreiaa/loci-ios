import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Saved (web: /saved; /favorites and /bookmarks redirect here). Places from
/// FavoritesService.GetFavorites, itineraries from ItineraryService.GetUserItineraries.
struct SavedView: View {
  enum Segment: String, CaseIterable { case places = "Places", itineraries = "Itineraries", lists = "Lists" }

  @State private var segment = Segment.places
  @State private var favorites: [Loci_Favorites_V1_FavoriteItem] = []
  @State private var itineraries: [Loci_Itinerary_UserSavedItinerary] = []
  @State private var loadedFavorites: Loaded<Loci_Favorites_V1_GetFavoritesResponse>?
  @State private var isLoading = true
  @State private var error: String?
  @State private var linked: AppLink?
  private let router = AppRouter.shared

  var body: some View {
    NavigationStack {
      List {
        Picker("Saved", selection: $segment) { ForEach(Segment.allCases, id: \.self) { Text($0.rawValue) } }
          .pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())

        switch segment {
        case .places:
          ForEach(favorites, id: \.id) { item in
            NavigationLink(value: item) {
              HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: SavedPlace.kindSymbol(item.contentType))
                  .foregroundStyle(Color.lociForest)
                  .frame(width: 20)
                  .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                  Text(item.itemName).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
                  HStack {
                    Text(SavedPlace.kindLabel(item.contentType))
                    if !item.cityName.isEmpty { Text(item.cityName) }
                    if !item.category.isEmpty { Text(item.category) }
                    if item.rating > 0 { Text(String(format: "★ %.1f", item.rating)) }
                  }
                  .lociCoordStyle(10)
                  if !item.notes.isEmpty { Text(item.notes).font(.lociCaption()).foregroundStyle(Color.lociMutedInk).lineLimit(2) }
                }
              }
            }
            .listRowBackground(Color.lociCard)
            .swipeActions { Button("Remove", role: .destructive) { Task { await remove(item) } } }
          }
        case .itineraries:
          ForEach(itineraries, id: \.id) { itinerary in
            NavigationLink(value: itinerary) {
              VStack(alignment: .leading, spacing: 3) {
                Text(itinerary.title).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
                HStack {
                  if itinerary.hasEstimatedDurationDays { Text("\(itinerary.estimatedDurationDays) days") }
                  if itinerary.hasCreatedAt { Text(itinerary.createdAt.date, style: .date) }
                }
                .lociCoordStyle(10)
              }
            }
            .listRowBackground(Color.lociCard)
            .swipeActions { Button("Delete", role: .destructive) { Task { await delete(itinerary) } } }
          }
        case .lists:
          EmptyView()
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(Color.lociPaper.ignoresSafeArea())
      .overlay {
        if !isLoading, segment == .places, favorites.isEmpty {
          ContentUnavailableView("No saved places", systemImage: "heart", description: Text("Save a place from any result and it lands here."))
        } else if !isLoading, segment == .itineraries, itineraries.isEmpty {
          ContentUnavailableView("No saved itineraries", systemImage: "bookmark", description: Text("Save an itinerary from its page."))
        } else if segment == .lists {
          ComingSoonPlaceholder(title: YouDestination.lists.title, systemImage: YouDestination.lists.systemImage)
        }
      }
      .navigationTitle("Saved")
      .navigationDestination(for: Loci_Itinerary_UserSavedItinerary.self) { SavedItineraryView(itinerary: $0) }
      .navigationDestination(for: Loci_Favorites_V1_FavoriteItem.self) { item in
        // Unsaving from the detail takes the row out here too; saving it
        // again puts it back where it was.
        SavedPlaceDetailView(item: item) { isSaved in
          if isSaved {
            if !favorites.contains(where: { $0.id == item.id }) { Task { await load() } }
          } else {
            favorites.removeAll { $0.id == item.id }
          }
        }
      }
      .navigationDestination(item: $linked) { AppLinkDestination(link: $0) }
      .refreshable { await load() }
      .errorAlert($error)
      .task { await load() }
      .onAppear(perform: openPending)
      .onChange(of: router.pendingLink) { openPending() }
    }
  }

  /// A `/lists/:id` link: the Lists segment, with the list pushed on top.
  private func openPending() {
    guard let link = router.takeLink(for: .saved) else { return }
    segment = .lists
    linked = link
  }

  /// The phone's copies first, then the server; offline keeps them and says so.
  private func load() async {
    isLoading = favorites.isEmpty && itineraries.isEmpty
    async let places = loadFavorites()
    async let saved = loadItineraries()
    let (loadedPlaces, loadedSaved) = await (places, saved)
    loadedFavorites = loadedPlaces
    if let value = loadedPlaces.value { favorites = value.favorites }
    if let value = loadedSaved.value { itineraries = value.itineraries }
    if case .missing(let reason) = loadedPlaces, case .missing = loadedSaved { error = reason.userMessage }
    isLoading = false
  }

  /// web: lib/api/favorites.ts — userId is required non-empty by validation and ignored by the server.
  private func loadFavorites() async -> Loaded<Loci_Favorites_V1_GetFavoritesResponse> {
    var request = Loci_Favorites_V1_GetFavoritesRequest()
    request.userID = AuthSessionManager.shared.currentUserID ?? "me"
    request.limit = 1000
    let sent = request
    return await cacheThrough(
      Loci_Favorites_V1_GetFavoritesResponse.self, kind: .saved, id: "favorites", onCached: { favorites = $0.value.favorites }
    ) {
      try await rpc("Could not load saved places.", sent) { await SavedAPI.favorites.getFavorites(request: $0, headers: [:]) }
    }
  }

  /// web: lib/api/itineraries.ts — page_size is capped at 100 by validation.
  private func loadItineraries() async -> Loaded<Loci_Itinerary_GetUserItinerariesResponse> {
    var request = Loci_Itinerary_GetUserItinerariesRequest()
    request.pagination.page = 1
    request.pagination.pageSize = 100
    let sent = request
    return await cacheThrough(
      Loci_Itinerary_GetUserItinerariesResponse.self, kind: .saved, id: "itineraries", onCached: { itineraries = $0.value.itineraries }
    ) {
      try await rpc("Could not load saved itineraries.", sent) { await SavedAPI.itineraries.getUserItineraries(request: $0, headers: [:]) }
    }
  }

  private func remove(_ item: Loci_Favorites_V1_FavoriteItem) async {
    var request = Loci_Favorites_V1_RemoveFromFavoritesRequest()
    request.userID = AuthSessionManager.shared.currentUserID ?? "me"
    request.itemID = item.itemID
    request.contentType = item.contentType
    do {
      _ = try await rpc("Could not remove it.", request) { await SavedAPI.favorites.removeFromFavorites(request: $0, headers: [:]) }
      favorites.removeAll { $0.id == item.id }
    } catch { self.error = error.userMessage }
  }

  private func delete(_ itinerary: Loci_Itinerary_UserSavedItinerary) async {
    var request = Loci_Itinerary_DeleteBookmarkRequest()
    request.itineraryID = itinerary.id
    do {
      _ = try await rpc("Could not delete it.", request) { await SavedAPI.itineraries.deleteBookmark(request: $0, headers: [:]) }
      itineraries.removeAll { $0.id == itinerary.id }
    } catch { self.error = error.userMessage }
  }
}

/// A saved itinerary: its markdown, and a way back to the session that made it.
struct SavedItineraryView: View {
  let itinerary: Loci_Itinerary_UserSavedItinerary

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text(itinerary.title).font(.lociDisplay(28))
        if itinerary.hasDescription_p, !itinerary.description_p.isEmpty { Text(itinerary.description_p).font(.lociBody()) }
        if !itinerary.markdownContent.isEmpty {
          Text((try? AttributedString(markdown: itinerary.markdownContent, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(itinerary.markdownContent))
            .font(.lociBody())
        }
        if itinerary.hasSessionID, !itinerary.sessionID.isEmpty {
          NavigationLink("Open the search that made it") {
            SearchResultsView(link: SessionLink(destination: .itinerary, sessionId: itinerary.sessionID, domain: "itinerary"))
          }
        }
      }
      .padding(LociTheme.defaultPadding)
    }
    .background(Color.lociPaper.ignoresSafeArea())
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { ShareLink(item: itinerary.markdownContent.isEmpty ? itinerary.title : itinerary.markdownContent) }
  }
}

nonisolated enum SavedAPI {
  static let favorites = Loci_Favorites_V1_FavoritesServiceClient(client: ConnectTransport.shared.protocolClient)
  static let itineraries = Loci_Itinerary_ItineraryServiceClient(client: ConnectTransport.shared.protocolClient)
}
