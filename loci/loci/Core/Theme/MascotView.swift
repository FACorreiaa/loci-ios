import SwiftUI

/// The moments Loci shows up for. Same list as the web's `MascotState`
/// (loci-client src/components/brand/Mascot.tsx). Each gets its own pose once
/// the 2026-10 pose set is approved; until a pose exists the state falls back
/// to the standing figure, which is the same character.
enum MascotState: String, CaseIterable {
  case idle, welcome, searching, thinking, discovering, navigating, success, empty, error, offline

  /// The asset for this state. No pose is approved yet, so every state is the
  /// standing figure; adding one is an imageset named `Mascot<State>` and a
  /// switch here.
  var imageName: String { "LociMascot" }
}

/// The mascot, sized by width. Decorative by default: wherever it appears, the
/// sentence beside it says what happened, so VoiceOver reads that, not a
/// description of the figure.
struct MascotView: View {
  var state: MascotState = .idle
  var width: CGFloat = 120
  var decorative = true
  /// A slow two-point bob. Off under Reduce Motion.
  var idle = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var lifted = false

  var body: some View {
    image.resizable().scaledToFit().frame(width: width)
      .offset(y: lifted ? -2 : 0)
      .onAppear {
        guard idle, !reduceMotion else { return }
        withAnimation(LociTheme.mascotIdle) { lifted = true }
      }
      .onChange(of: reduceMotion) { _, reduce in
        if reduce { lifted = false }
      }
  }

  private var image: Image {
    decorative ? Image(decorative: state.imageName) : Image(state.imageName)
  }
}

/// "Nothing here yet", "you're offline", "that went wrong": a mascot over the
/// system empty state. Use where the moment earns a character (saved, trips,
/// lists, recents, no results, offline); everywhere else a plain
/// `ContentUnavailableView` with an SF Symbol is the right call.
struct LociEmptyState<Actions: View>: View {
  let title: String
  var message: String?
  var mascot: MascotState = .empty
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    ContentUnavailableView {
      VStack(spacing: 16) {
        MascotView(state: mascot, width: 104, idle: true)
        Text(title).font(.lociTitle(22)).foregroundStyle(Color.lociInk)
      }
    } description: {
      if let message { Text(message).font(.lociBody(15)).foregroundStyle(Color.lociMutedInk) }
    } actions: {
      actions()
    }
  }
}

extension LociEmptyState where Actions == EmptyView {
  init(title: String, message: String? = nil, mascot: MascotState = .empty) {
    self.init(title: title, message: message, mascot: mascot) { EmptyView() }
  }
}
