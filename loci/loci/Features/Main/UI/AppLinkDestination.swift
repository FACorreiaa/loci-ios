import SwiftUI

/// The page an `AppLink` opens, pushed by the tab that owns it
/// (`AppRouter.tab(for:)`). Trips, Recents, Lists, packs and Contribute are real; the rest are placeholders until
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
    case .sharedTrip(let code): SharedTripView(source: .code(code))
    case .invite(let code): InviteView(code: code)
    case .user(let username): UserProfileView(username: username)
    case .friends: YouDestination.friends.screen
    case .friendTrip(let id): SharedTripView(source: .tripID(id))
    case .leaderboard: YouDestination.leaderboard.screen
    case .progress: YouDestination.progress.screen
    case .resetPassword(let token): ResetPasswordView(token: token)
    case .confirmEmail(let token): ConfirmEmailView(token: token)
    case .shared(let code): SharedContentView(code: code)
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
