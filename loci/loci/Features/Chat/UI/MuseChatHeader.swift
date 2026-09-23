import SwiftUI

/// The Muse chat header (apps/_reviews/muse-chat-contract.md): a 40pt circle
/// on the left, a "New chat" pill on the right, and Loci's 110pt avatar in the
/// middle with a pill naming the agent and its status.
///
/// Place it with `.safeAreaInset(edge: .top)` so the transcript scrolls under
/// it; it draws its own 120pt canvas → clear scrim, so it needs no blur.
struct MuseChatHeader: View {
  var name = "Loci"
  var status = "Ready"
  var leadingSystemImage = "list.bullet"
  var leadingLabel = "Conversations"
  var onLeading: () -> Void = {}
  var onNewChat: () -> Void = {}

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack(alignment: .top) {
      HStack {
        Button(leadingLabel, systemImage: leadingSystemImage, action: onLeading)
          .labelStyle(.iconOnly)
          .font(.body.weight(.semibold))
          .frame(width: LociTheme.Muse.headerButtonSize, height: LociTheme.Muse.headerButtonSize)
          .background(Color.musePill, in: Circle())
          .contentShape(.rect.inset(by: -2))
        Spacer()
        Button("New chat", action: onNewChat).buttonStyle(MusePillButtonStyle())
      }
      .foregroundStyle(Color.museText)
      .frame(height: 56)
      .padding(.horizontal, LociTheme.defaultPadding)

      VStack(spacing: 8) {
        MuseAvatar()
        identity
      }
      .padding(.horizontal, 64)
    }
    .padding(.bottom, 8)
    .frame(maxWidth: .infinity)
    .background(alignment: .top) { MuseScrim().ignoresSafeArea(edges: .top) }
  }

  private var identity: some View {
    VStack(spacing: 1) {
      Text(name).font(.museName).foregroundStyle(Color.museText)
      Text(status)
        .font(.museStatus)
        .foregroundStyle(Color.museTextSecondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .contentTransition(reduceMotion ? .identity : .opacity)
        .animation(reduceMotion ? nil : LociTheme.reducedFade, value: status)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .background(Color.musePill, in: RoundedRectangle(cornerRadius: 999, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

/// Loci's avatar. Idle art only; the working ring arrives with stage B.
/// It never floats or bobs, so Reduce Motion needs nothing extra here.
struct MuseAvatar: View {
  var body: some View {
    Image("LociMascot")
      .resizable()
      .scaledToFit()
      .padding(.top, 14)
      .padding(.bottom, 8)
      .frame(width: LociTheme.Muse.avatarSize, height: LociTheme.Muse.avatarSize)
      .background(Color.musePill, in: Circle())
      .clipShape(Circle())
      .overlay(Circle().stroke(Color.museCanvas, lineWidth: 3))
      .accessibilityHidden(true)
  }
}

/// Solid canvas under the status bar, then a 120pt canvas → clear gradient.
/// The required fallback for blur (Reduce Transparency, Low Power).
struct MuseScrim: View {
  var body: some View {
    VStack(spacing: 0) {
      Color.museCanvas
      LinearGradient(colors: [.museCanvas, .museCanvas.opacity(0)], startPoint: .top, endPoint: .bottom)
        .frame(height: LociTheme.Muse.scrimHeight)
    }
    .allowsHitTesting(false)
  }
}

/// A `musePill` capsule button: "New chat", Save, Share, Stop.
struct MusePillButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.museName)
      .foregroundStyle(Color.museText)
      .padding(.horizontal, 16)
      .frame(minHeight: LociTheme.Muse.headerButtonSize)
      .background(Color.musePill, in: Capsule())
      .contentShape(Capsule())
      .opacity(configuration.isPressed ? 0.6 : isEnabled ? 1 : 0.5)
  }
}

/// One chat bubble. No avatar and no name label: the header says who is talking.
struct MuseBubble<Content: View>: View {
  enum Role { case user, agent }

  let role: Role
  @ViewBuilder var content: Content

  var body: some View {
    content
      .font(.museBody)
      .foregroundStyle(role == .user ? Color.museUserText : Color.museText)
      .tint(role == .user ? Color.museUserText : Color.lociForest)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(
        role == .user ? Color.museUserBubble : Color.museAgentBubble,
        in: RoundedRectangle(cornerRadius: LociTheme.Muse.bubbleRadius, style: .continuous)
      )
      .containerRelativeFrame(.horizontal, alignment: role == .user ? .trailing : .leading) { length, _ in
        (length - LociTheme.defaultPadding * 2) * (role == .user ? LociTheme.Muse.userBubbleWidth : LociTheme.Muse.agentBubbleWidth)
      }
      .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
  }
}

// MARK: - Previews

#Preview("Header — idle") {
  ScrollView {
    VStack(spacing: 12) {
      MuseBubble(role: .user) { Text("3 days in Lisbon with kids") }
      MuseBubble(role: .agent) { Text("Here is a gentle plan: mornings by the river, afternoons in the shade, nothing more than 20 minutes on foot.") }
    }
    .padding(LociTheme.defaultPadding)
  }
  .background(Color.museCanvas.ignoresSafeArea())
  .safeAreaInset(edge: .top, spacing: 0) { MuseChatHeader() }
}

#Preview("Header — long status") {
  VStack {
    MuseChatHeader(status: "is still working — you can leave this screen and come back later")
    Spacer()
  }
  .background(Color.museCanvas.ignoresSafeArea())
}
