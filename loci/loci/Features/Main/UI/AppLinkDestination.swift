import SwiftUI

/// The page an `AppLink` opens, pushed by the tab that owns it
/// (`AppRouter.tab(for:)`). Trips, Recents, Lists and packs are real; the rest are placeholders until
/// their phase of the parity plan lands (`docs/ios/14-you-hub-and-app-links.md`).
struct AppLinkDestination: View {
  let link: AppLink

  var body: some View {
    switch link {
    case .trip(let id): TripEditorView(tripID: id)
    case .list(let id): ListDetailView(listID: id)
    case .pack(let slug): PackDetailView(slug: slug)
    case .recents: YouDestination.recents.screen
    case .contribute: YouDestination.contribute.screen
    }
  }
}

/// A screen that exists in the navigation but not yet in the app.
struct ComingSoonView: View {
  let title: String
  let systemImage: String

  var body: some View {
    ComingSoonPlaceholder(title: title, systemImage: systemImage)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
  }
}

/// The placeholder on its own, for a screen that shows it inside itself.
struct ComingSoonPlaceholder: View {
  let title: String
  let systemImage: String

  var body: some View {
    ContentUnavailableView(title, systemImage: systemImage, description: Text("Coming in the next update."))
  }
}
