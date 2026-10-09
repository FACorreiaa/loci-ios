import SwiftUI

public struct MainTabView: View {
  public var onSignOut: () -> Void = {}

  public init(onSignOut: @escaping () -> Void = {}) { self.onSignOut = onSignOut }

  @Bindable private var router = AppRouter.shared
  @Bindable private var pushPrimer = PushPrimer.shared
  @Bindable private var tripSetup = TripSetupOffer.shared
  @Environment(\.scenePhase) private var scenePhase

  public var body: some View {
    TabView(selection: $router.selectedTab) {
      Tab("Discover", systemImage: "magnifyingglass", value: AppRouter.Tab.discover) { DiscoverView() }

      Tab("Calendar", systemImage: "calendar", value: AppRouter.Tab.calendar) { CalendarView() }

      Tab("Assistant", systemImage: "bubble.left.and.bubble.right.fill", value: AppRouter.Tab.assistant) { AssistantView() }

      Tab("Saved", systemImage: "bookmark.fill", value: AppRouter.Tab.saved) { SavedView() }

      Tab("Profile", systemImage: "person.fill", value: AppRouter.Tab.profile) { ProfileView(onSignOut: onSignOut) }
    }.tint(.lociForest)
      // Swiping the primer away is a "not now"; after a button this is a no-op.
      .sheet(isPresented: $pushPrimer.isAsking, onDismiss: { pushPrimer.respond(false) }) {
        PushPrimerSheet(primer: pushPrimer)
      }
      // Once, after the first sign-in of an account with no profile (web: /trip-setup).
      .fullScreenCover(isPresented: $tripSetup.isPresenting) {
        TripSetupView { tripSetup.dismiss() }
      }
      // "+10 · Visited Pantheon" when something earns points.
      .overlay(alignment: .top) { PointsToastOverlay() }
      // The day's check-in: signed in and in front, once per local day.
      .task { await ProgressReporter.checkInIfNeeded() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await ProgressReporter.checkInIfNeeded() } }
      }
  }
}
