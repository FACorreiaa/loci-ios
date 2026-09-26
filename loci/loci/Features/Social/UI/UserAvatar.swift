import LociConnectProto
import SwiftUI

/// A user's photo, or their initials on the brand tint when they have none.
struct UserAvatar: View {
  let user: Loci_Social_PublicUser
  var size: CGFloat = 40

  var body: some View {
    ZStack {
      Circle().fill(Color.lociCoral.opacity(0.15))
      if let url = URL(string: user.avatarURL), !user.avatarURL.isEmpty {
        AsyncImage(url: url) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          initials
        }
      } else {
        initials
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .accessibilityHidden(true)
  }

  private var initials: some View {
    Text(user.initials).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(Color.lociCoral)
  }
}

/// A person in a list: avatar, name, @username and a trailing control.
struct PersonRow<Trailing: View>: View {
  let user: Loci_Social_PublicUser
  var subtitle: String?
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 12) {
      UserAvatar(user: user)
      VStack(alignment: .leading, spacing: 2) {
        Text(user.shownName).font(.lociHeadline(16)).foregroundStyle(Color.lociInk).lineLimit(1)
        Text(subtitle ?? handle).font(.lociCaption()).foregroundStyle(Color.lociMutedInk).lineLimit(1)
      }
      Spacer(minLength: 8)
      trailing
    }
    .padding(.vertical, 2)
  }

  /// "@ana · Lisbon", leaving out whichever is missing.
  private var handle: String {
    var parts: [String] = []
    if !user.username.isEmpty { parts.append("@\(user.username)") }
    if !user.homeCity.isEmpty { parts.append(user.homeCity) }
    return parts.joined(separator: " · ")
  }
}
