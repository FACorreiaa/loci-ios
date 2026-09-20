import SwiftUI

public struct MainTabView: View {
  public var onSignOut: () -> Void = {}

  public init(onSignOut: @escaping () -> Void = {}) { self.onSignOut = onSignOut }

  public var body: some View {
    TabView {
      DiscoverView().tabItem { Label("Discover", systemImage: "magnifyingglass") }

      TripsView().tabItem { Label("Trips", systemImage: "map.fill") }

      ChatView().tabItem { Label("Assistant", systemImage: "bubble.left.and.bubble.right.fill") }

      FavoritesView().tabItem { Label("Saved", systemImage: "bookmark.fill") }

      ProfileView(onSignOut: onSignOut).tabItem { Label("Profile", systemImage: "person.fill") }
    }.tint(.lociCoral)
  }
}
