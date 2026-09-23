import SwiftUI

/// The Muse chat header (apps/_reviews/muse-chat-contract.md): a 40pt circle
/// on the left, a "New chat" pill on the right, and Loci's 110pt avatar in the
/// middle with a pill naming the agent and its status.
///
/// `activity` comes from `MuseActivity.resolve`: the status line, and the ring
/// that says Loci is working.
///
/// Place it with `.safeAreaInset(edge: .top)` so the transcript scrolls under
/// it; it draws its own 120pt canvas → clear scrim, so it needs no blur.
struct MuseChatHeader: View {
  var name = "Loci"
  var activity = MuseActivity.ready
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
        MuseAvatar(mood: activity.mood)
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
      Text(activity.status)
        .font(.museStatus)
        .foregroundStyle(Color.museTextSecondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .contentTransition(reduceMotion ? .identity : .opacity)
        .animation(reduceMotion ? nil : LociTheme.reducedFade, value: activity.status)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .background(Color.musePill, in: RoundedRectangle(cornerRadius: 999, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

/// Loci's avatar: idle art always (there is no working art), with a ring for
/// the mood. It never floats or bobs.
struct MuseAvatar: View {
  var mood: MuseMood = .idle

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var celebrationScale: CGFloat = 1

  var body: some View {
    art
      .overlay { MuseRing(mood: mood).padding(-LociTheme.Muse.ringInset) }
      .scaleEffect(celebrationScale)
      .onChange(of: mood) { _, new in
        guard new == .celebrating, !reduceMotion else { return }
        withAnimation(LociTheme.defaultSpring) { celebrationScale = 1.06 } completion: {
          withAnimation(LociTheme.defaultSpring) { celebrationScale = 1 }
        }
      }
  }

  private var art: some View {
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

/// The ring around the avatar. Working: a coral arc going round (a full static
/// ring under Reduce Motion). Listening: a faint full ring. Celebrating: a full
/// coral ring. Idle: none.
struct MuseRing: View {
  let mood: MuseMood

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      switch mood {
      case .idle:
        EmptyView()
      case .listening:
        Circle().stroke(Color.museRing.opacity(0.45), lineWidth: LociTheme.Muse.ringWidth)
      case .celebrating:
        Circle().stroke(Color.museRing, lineWidth: LociTheme.Muse.ringWidth)
      case .working:
        if reduceMotion {
          Circle().stroke(Color.museRing, lineWidth: LociTheme.Muse.ringWidth)
        } else {
          spinningArc
        }
      }
    }
    .animation(reduceMotion ? nil : LociTheme.reducedFade, value: mood)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// One turn every 1.4s, driven by the frame clock so it never snaps back.
  private var spinningArc: some View {
    TimelineView(.animation) { context in
      let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
      ZStack {
        Circle().stroke(Color.museRing.opacity(0.18), lineWidth: LociTheme.Muse.ringWidth)
        Circle()
          .trim(from: 0, to: 0.32)
          .stroke(
            AngularGradient(colors: [Color.museRing.opacity(0), Color.museRing], center: .center, startAngle: .degrees(0), endAngle: .degrees(115)),
            style: StrokeStyle(lineWidth: LociTheme.Muse.ringWidth, lineCap: .round)
          )
          .rotationEffect(.degrees(turn * 360))
      }
    }
    .transition(.opacity)
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
      MuseBubble(role: .agent) {
        Text("Here is a gentle plan: mornings by the river, afternoons in the shade, nothing more than 20 minutes on foot.")
      }
    }
    .padding(LociTheme.defaultPadding)
  }
  .background(Color.museCanvas.ignoresSafeArea())
  .safeAreaInset(edge: .top, spacing: 0) { MuseChatHeader() }
}

#Preview("Header — states") {
  ScrollView {
    VStack(spacing: 24) {
      MuseChatHeader(activity: .resolve(status: .streaming))
      MuseChatHeader(activity: .resolve(status: .streaming, progressStage: "Checking opening hours"))
      MuseChatHeader(activity: .resolve(status: .detached))
      MuseChatHeader(activity: .resolve(status: .completed, flash: .celebrating(places: 7)))
      MuseChatHeader(activity: .resolve(status: .idle, isListening: true))
    }
  }
  .background(Color.museCanvas.ignoresSafeArea())
}

extension View {
  /// Hold the celebrating / hit-a-snag flash that a search earns when it ends,
  /// then clear it after its duration so the header settles on Ready.
  func museFlash(_ flash: Binding<MuseActivity.Flash?>, status: SearchState.Status?, places: Int) -> some View {
    onChange(of: status) { old, new in
      if let earned = MuseActivity.flash(from: old, to: new, places: places) { flash.wrappedValue = earned }
    }
    .task(id: flash.wrappedValue) {
      guard let current = flash.wrappedValue else { return }
      try? await Task.sleep(for: current.duration)
      if !Task.isCancelled, flash.wrappedValue == current { flash.wrappedValue = nil }
    }
  }
}
