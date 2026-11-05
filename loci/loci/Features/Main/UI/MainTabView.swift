import SwiftUI

public struct MainTabView: View {
  public var onSignOut: () -> Void = {}

  public init(onSignOut: @escaping () -> Void = {}) { self.onSignOut = onSignOut }

  @Bindable private var router = AppRouter.shared
  @Bindable private var pushPrimer = PushPrimer.shared
  @Bindable private var tripSetup = TripSetupOffer.shared
  private let askLoci = AskLociController.shared
  @Environment(\.scenePhase) private var scenePhase

  public var body: some View {
    TabView(selection: tabSelection) {
      Tab("Discover", systemImage: "magnifyingglass", value: AppRouter.Tab.discover) { DiscoverView() }

      Tab("Calendar", systemImage: "calendar", value: AppRouter.Tab.calendar) { CalendarView() }

      Tab("Assistant", systemImage: "bubble.left.and.bubble.right.fill", value: AppRouter.Tab.assistant) { AssistantView() }

      Tab("Saved", systemImage: "bookmark.fill", value: AppRouter.Tab.saved) { SavedView() }

      Tab("Profile", systemImage: "person.fill", value: AppRouter.Tab.profile) { ProfileView(onSignOut: onSignOut) }
    }.tint(.lociForest)
      // Swiping the primer away is a "not now"; after a button this is a no-op.
      .sheet(isPresented: primerIsShowing, onDismiss: { pushPrimer.respond(false) }) {
        PushPrimerSheet(primer: pushPrimer)
      }
      // Once, after the first sign-in of an account with no profile (web: /trip-setup).
      .fullScreenCover(isPresented: tripSetupIsShowing) {
        TripSetupView { tripSetup.dismiss() }
      }
      // "+10 · Visited Pantheon" when something earns points.
      .overlay(alignment: .top) { PointsToastOverlay() }
      // "How was it?" for a place visited a while ago, or just left.
      .overlay(alignment: .bottom) { RatePromptOverlay() }
      // A hold on the Assistant tab: Ask Loci, over everything else on screen.
      .background { AskLociTabHold { askLoci.open(listen: true) } }
      .overlay { AskLociOverlay() }
      // The day's check-in: signed in and in front, once per local day.
      .task {
        await ProgressReporter.checkInIfNeeded()
        await TasteFences.shared.refresh()
        await VisitLogger.shared.refresh()
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .background { askLoci.didEnterBackground() }
        if phase == .active {
          RatePrompter.shared.refresh()
          Task {
            await ProgressReporter.checkInIfNeeded()
            await TasteFences.shared.refresh()
            await VisitLogger.shared.refresh()
          }
        }
      }
  }

  // The finger lifting from a hold on the tab bar must not change tabs behind Ask Loci.
  private var tabSelection: Binding<AppRouter.Tab> {
    Binding(
      get: { router.selectedTab },
      set: { if !askLoci.isOpen { router.selectedTab = $0 } }
    )
  }

  // Neither of these interrupts Ask Loci; they wait until it closes.
  private var primerIsShowing: Binding<Bool> {
    Binding(get: { pushPrimer.isAsking && !askLoci.isOpen }, set: { pushPrimer.isAsking = $0 })
  }

  private var tripSetupIsShowing: Binding<Bool> {
    Binding(get: { tripSetup.isPresenting && !askLoci.isOpen }, set: { tripSetup.isPresenting = $0 })
  }
}
