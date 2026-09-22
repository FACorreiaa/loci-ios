import SwiftUI

public struct MainTabView: View {
  public var onSignOut: () -> Void = {}

  public init(onSignOut: @escaping () -> Void = {}) { self.onSignOut = onSignOut }

  @Bindable private var router = AppRouter.shared

  public var body: some View {
    TabView(selection: $router.selectedTab) {
      DiscoverView().tabItem { Label("Discover", systemImage: "magnifyingglass") }.tag(AppRouter.Tab.discover)

      CalendarView().tabItem { Label("Calendar", systemImage: "calendar") }.tag(AppRouter.Tab.calendar)

      ChatView().tabItem { Label("Assistant", systemImage: "bubble.left.and.bubble.right.fill") }.tag(AppRouter.Tab.assistant)

      FavoritesView().tabItem { Label("Saved", systemImage: "bookmark.fill") }.tag(AppRouter.Tab.saved)

      ProfileView(onSignOut: onSignOut).tabItem { Label("Profile", systemImage: "person.fill") }.tag(AppRouter.Tab.profile)
    }.tint(.lociForest)
  }
}
