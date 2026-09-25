import SwiftUI

public struct MainTabView: View {
  public var onSignOut: () -> Void = {}

  public init(onSignOut: @escaping () -> Void = {}) { self.onSignOut = onSignOut }

  @Bindable private var router = AppRouter.shared
  @Bindable private var pushPrimer = PushPrimer.shared
  @Bindable private var tripSetup = TripSetupOffer.shared

  public var body: some View {
    TabView(selection: $router.selectedTab) {
      DiscoverView().tabItem { Label("Discover", systemImage: "magnifyingglass") }.tag(AppRouter.Tab.discover)

      CalendarView().tabItem { Label("Calendar", systemImage: "calendar") }.tag(AppRouter.Tab.calendar)

      AssistantView().tabItem { Label("Assistant", systemImage: "bubble.left.and.bubble.right.fill") }.tag(AppRouter.Tab.assistant)

      SavedView().tabItem { Label("Saved", systemImage: "bookmark.fill") }.tag(AppRouter.Tab.saved)

      ProfileView(onSignOut: onSignOut).tabItem { Label("Profile", systemImage: "person.fill") }.tag(AppRouter.Tab.profile)
    }.tint(.lociForest)
      // Swiping the primer away is a "not now"; after a button this is a no-op.
      .sheet(isPresented: $pushPrimer.isAsking, onDismiss: { pushPrimer.respond(false) }) {
        PushPrimerSheet(primer: pushPrimer)
      }
      // Once, after the first sign-in of an account with no profile (web: /trip-setup).
      .fullScreenCover(isPresented: $tripSetup.isPresenting) {
        TripSetupView { tripSetup.dismiss() }
      }
  }
}
