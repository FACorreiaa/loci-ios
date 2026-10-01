import LociConnectProto
import SwiftUI

/// Someone's invite link opened in the app (web: /invite/:code): one tap to
/// become friends.
struct InviteView: View {
  let code: String

  @State private var invite: Loci_Social_GetInviteResponse?
  @State private var failure: InviteFailure?
  @State private var isAccepting = false
  @State private var friend: Loci_Social_PublicUser?
  @State private var error: String?

  var body: some View {
    VStack(spacing: 16) {
      if let invite {
        let inviter = invite.invite.inviter
        UserAvatar(user: inviter, size: 88)
        Text("\(inviter.shownName) wants to travel with you")
          .font(.lociDisplay(24)).multilineTextAlignment(.center).foregroundStyle(Color.lociInk)
        Text("Friends on Loci see each other's shared trips and can save them.")
          .font(.lociCaption(15)).multilineTextAlignment(.center).foregroundStyle(Color.lociMutedInk)
        switch Relationship(invite.relationship) {
        case .friends:
          NavigationLink("See their trips") { UserProfileView(username: inviter.username) }.buttonStyle(.bordered)
        case .isSelf:
          Text("This is your own invite. Send it to a friend.").font(.lociCaption())
        default:
          Button(isAccepting ? "Connecting…" : "Become friends") { accept() }
            .buttonStyle(.borderedProminent).tint(.lociCoralFill).controlSize(.large).disabled(isAccepting)
        }
      } else if let failure {
        ContentUnavailableView(failure.title(for: .open), systemImage: "link.badge.plus", description: Text(failure.hint))
      } else {
        ProgressView()
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.lociPaper.ignoresSafeArea())
    .navigationTitle("Invite").navigationBarTitleDisplayMode(.inline)
    .navigationDestination(item: $friend) { UserProfileView(username: $0.username) }
    .errorAlert($error)
    .task {
      do { invite = try await SocialAPI.invite(code: code) } catch { failure = InviteFailure(error) }
    }
  }

  private func accept() {
    isAccepting = true
    Task {
      defer { isAccepting = false }
      do {
        friend = try await SocialAPI.acceptInvite(code: code)
        Analytics.capture(.friendAdded, ["via": "invite"])
      } catch { self.error = InviteFailure(error).title(for: .accept) }
    }
  }
}
