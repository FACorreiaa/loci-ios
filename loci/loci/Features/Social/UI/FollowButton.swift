import LociConnectProto
import SwiftUI

/// The one control for "do I follow this person" (web: FollowButton).
/// Following someone who follows you makes you friends; a private account
/// answers with a request. Unfollowing asks first, since a friend loses your
/// friends-only trips.
struct FollowButton: View {
  let user: Loci_Social_PublicUser
  @Binding var edge: FollowEdge
  /// Where the follow came from, for analytics: profile, search, contacts, facebook, list.
  var via = "profile"

  @State private var isBusy = false
  @State private var confirmUnfollow = false
  @State private var error: String?

  var body: some View {
    Group {
      switch edge.state {
      case .notFollowing:
        Button(edge.title, systemImage: "person.badge.plus") { run(follow) }
          .buttonStyle(.borderedProminent).tint(.lociCoralFill)
      case .requested:
        Button(edge.title) { run(unfollow) }
          .buttonStyle(.bordered)
          .accessibilityHint("Cancels your request to follow \(user.shownName)")
      case .following:
        Button(edge.title, systemImage: edge.followsYou ? "person.2.fill" : "person.fill.checkmark") { confirmUnfollow = true }
          .buttonStyle(.bordered)
      case .blocked:
        Button(edge.title) { run { try await SocialAPI.unblock(userID: user.id); edge.state = .notFollowing } }.buttonStyle(.bordered)
      case .isSelf, .unknown:
        EmptyView()
      }
    }
    .tint(.lociCoral)
    .disabled(isBusy)
    .confirmationDialog("Unfollow \(user.shownName)?", isPresented: $confirmUnfollow, titleVisibility: .visible) {
      Button("Unfollow", role: .destructive) { run(unfollow) }
    } message: {
      if edge.followsYou { Text("You stop being friends, and they no longer see the trips you share with friends.") }
    }
    .errorAlert($error)
  }

  private func follow() async throws {
    let back = edge.followsYou
    edge = try await SocialAPI.follow(userID: user.id)
    Analytics.capture(.follow, ["state": edge.state == .requested ? "requested" : "following", "friends": edge.isFriend, "back": back, "via": via])
    if edge.isFriend { Analytics.capture(.friendAdded, ["via": via]) }
  }

  /// Also withdraws a request still waiting.
  private func unfollow() async throws {
    try await SocialAPI.unfollow(userID: user.id)
    edge.state = .notFollowing
  }

  private func run(_ action: @escaping @MainActor () async throws -> Void) {
    isBusy = true
    Task {
      defer { isBusy = false }
      do { try await action() } catch { self.error = error.userMessage }
    }
  }
}
