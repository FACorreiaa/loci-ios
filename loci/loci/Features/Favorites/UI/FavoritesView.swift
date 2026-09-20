import Connect
import LociConnectProto
import SwiftUI

public struct FavoritesView: View {
  @State private var favorites: [Loci_Favorites_V1_FavoriteItem] = []
  @State private var isLoading: Bool = false
  @State private var errorMessage: String?

  private let client: Loci_Favorites_V1_FavoritesServiceClient

  public init(
    client: Loci_Favorites_V1_FavoritesServiceClient = Loci_Favorites_V1_FavoritesServiceClient(client: ConnectTransport.shared.protocolClient)
  ) { self.client = client }

  public var body: some View {
    NavigationStack {
      VStack {
        if isLoading {
          Spacer()
          ProgressView()
          Spacer()
        } else if let errorMessage {
          Spacer()
          VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.lociCoral)
            Text(errorMessage).font(.subheadline).foregroundColor(.lociInk.opacity(0.7))
            Button("Retry") { loadFavorites() }.foregroundColor(.lociCoral)
          }.padding()
          Spacer()
        } else if favorites.isEmpty {
          Spacer()
          VStack(spacing: 16) {
            Image(systemName: "bookmark.circle.fill").font(.system(size: 64)).foregroundColor(.lociCoral.opacity(0.8))

            Text("No Saved Places Yet").font(.title3.weight(.bold)).foregroundColor(.lociInk)

            Text("Tap the bookmark icon on any destination or restaurant to save it to your collection.").font(.subheadline).foregroundColor(
              .lociInk.opacity(0.7)
            ).multilineTextAlignment(.center).padding(.horizontal, 36)
          }
          Spacer()
        } else {
          List(favorites, id: \.id) { item in
            VStack(alignment: .leading, spacing: 4) {
              Text(item.itemName).font(.headline).foregroundColor(.lociInk)
              if !item.cityName.isEmpty { Text(item.cityName).font(.subheadline).foregroundColor(.lociInk.opacity(0.7)) }
            }.padding(.vertical, 6).listRowBackground(Color.lociCard)
          }.listStyle(.insetGrouped).scrollContentBackground(.hidden)
        }
      }.background(Color.lociPaper.ignoresSafeArea()).navigationTitle("Saved").toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            loadFavorites()
          } label: {
            Image(systemName: "arrow.clockwise")
          }
        }
      }
    }.task { loadFavorites() }
  }

  private func loadFavorites() {
    guard let userId = AuthSessionManager.shared.currentUserID, !userId.isEmpty else { return }
    isLoading = true
    errorMessage = nil

    Task {
      var headers: Connect.Headers = [:]
      if let token = try? await AuthSessionManager.shared.validAccessToken() { headers["Authorization"] = ["Bearer \(token)"] }

      var request = Loci_Favorites_V1_GetFavoritesRequest()
      request.userID = userId

      let response = await client.getFavorites(request: request, headers: headers)
      await MainActor.run {
        self.isLoading = false
        if let msg = response.message { self.favorites = msg.favorites } else if let err = response.error { self.errorMessage = err.message }
      }
    }
  }
}
