import LociConnectProto
import SwiftUI

/// Plays a recap as full-screen story cards: tap right for the next card,
/// left for the previous one, hold to pause, swipe down to close. Web:
/// components/recap/StoryPlayer.tsx.
struct RecapStoryView: View {
  @Bindable var store: RecapStore
  let recap: Loci_Recap_Recap
  var onClose: () -> Void

  /// How long each card stays up.
  static let cardSeconds: Double = 7
  private static let holdSeconds: Double = 0.22
  private static let swipeClose: CGFloat = 90

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var index = 0
  @State private var progress: Double = 0
  @State private var paused = false
  @State private var appeared = false
  @State private var pressStart: Date?
  @State private var heldToPause = false

  private var cards: [Loci_Recap_RecapCard] { RecapRules.playable(recap.cards) }
  private var current: Loci_Recap_RecapCard? { cards.indices.contains(index) ? cards[index] : nil }

  var body: some View {
    GeometryReader { geo in
      let size = Self.fit(geo.size)
      let unit = RecapUnit(u: size.width / 100)
      ZStack {
        Color.black.ignoresSafeArea()
        ZStack(alignment: .top) {
          if let current {
            RecapCardView(recap: recap, card: current, appeared: appeared || reduceMotion, unit: unit).id(current.id).transition(.opacity)
              .accessibilityElement(children: .contain).accessibilityLabel("Card \(index + 1) of \(cards.count)")
          }
          chrome(unit: unit, light: current?.isLight ?? false)
        }.frame(width: size.width, height: size.height).clipShape(RoundedRectangle(cornerRadius: 22)).contentShape(Rectangle()).gesture(
          pressGesture(width: size.width)
        ).accessibilityAction(named: "Next card") { advance(1) }.accessibilityAction(named: "Previous card") { advance(-1) }.accessibilityAction(
          named: paused ? "Play" : "Pause"
        ) { paused.toggle() }.accessibilityAction(.escape) { onClose() }
        if store.isOwner, let current { actions(for: current).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 12) }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }.statusBarHidden().task(id: index) { await play() }.sheet(item: $store.sharing) { item in
      ActivitySheet(items: item.activityItems).presentationDetents([.medium, .large])
    }.errorAlert($store.error)
  }

  /// The largest 9:16 box that fits, leaving room for the share buttons.
  static func fit(_ size: CGSize) -> CGSize {
    let height = min(size.height - 72, size.width * 16 / 9)
    return CGSize(width: height * 9 / 16, height: height)
  }

  private func chrome(unit: RecapUnit, light: Bool) -> some View {
    VStack(spacing: 8) {
      HStack(spacing: 4) {
        ForEach(cards.indices, id: \.self) { i in
          GeometryReader { bar in
            Capsule().fill((light ? RecapPalette.ink : .white).opacity(0.25)).overlay(alignment: .leading) {
              Capsule().fill(light ? RecapPalette.ink : .white).frame(width: bar.size.width * (i < index ? 1 : i == index ? progress : 0))
            }
          }.frame(height: 3)
        }
      }
      HStack {
        HStack(spacing: 6) {
          Circle().fill(RecapPalette.coral).frame(width: 8, height: 8)
          Text("LOCI").font(.custom("Space Mono", fixedSize: 10)).tracking(1.4)
        }
        Spacer()
        if paused { Text("PAUSED").font(.custom("Space Mono", fixedSize: 10)).tracking(1.4) }
        Button("Close recap", systemImage: "xmark", action: onClose).labelStyle(.iconOnly).frame(width: 36, height: 36).contentShape(Rectangle())
      }.foregroundStyle(light ? RecapPalette.ink.opacity(0.75) : RecapPalette.cream.opacity(0.8))
    }.padding(.horizontal, 12).padding(.top, 12).accessibilityElement(children: .contain)
  }

  private func actions(for card: Loci_Recap_RecapCard) -> some View {
    HStack(spacing: 8) {
      Button {
        Task { await store.shareImage(of: card) }
      } label: {
        Label(store.isPreparingShare ? "Making…" : "Save image", systemImage: "arrow.down.to.line")
      }.buttonStyle(RecapPillStyle(primary: false))
      Button {
        Task { await store.shareLink() }
      } label: {
        Label("Share link", systemImage: "link")
      }.buttonStyle(RecapPillStyle(primary: true))
    }.disabled(store.isPreparingShare)
  }

  private func pressGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0).onChanged { _ in
      guard pressStart == nil else { return }
      pressStart = .now
      Task {
        try? await Task.sleep(for: .seconds(Self.holdSeconds))
        if pressStart != nil, !paused {
          heldToPause = true
          paused = true
        }
      }
    }.onEnded { value in
      pressStart = nil
      if value.translation.height > Self.swipeClose {
        onClose()
        return
      }
      if heldToPause {
        heldToPause = false
        paused = false
        return
      }
      advance(value.location.x < width / 3 ? -1 : 1)
    }
  }

  private func advance(_ step: Int) {
    let next = index + step
    if next >= cards.count {
      paused = true
      progress = 1
      return
    }
    index = max(0, next)
  }

  /// Runs the current card's clock; a new index restarts it.
  private func play() async {
    progress = 0
    appeared = false
    try? await Task.sleep(for: .milliseconds(30))
    withAnimation { appeared = true }
    let tick = 0.05
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(tick))
      guard !paused else { continue }
      progress = min(1, progress + tick / Self.cardSeconds)
      if progress >= 1 {
        advance(1)
        return
      }
    }
  }
}

private struct RecapPillStyle: ButtonStyle {
  let primary: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.custom("Space Mono", fixedSize: 11).weight(.bold)).textCase(.uppercase).padding(.horizontal, 14).padding(.vertical, 9)
      .foregroundStyle(primary ? RecapPalette.cream : RecapPalette.ink).background(
        primary ? RecapPalette.coralDeep : RecapPalette.cream.opacity(0.95),
        in: Capsule()
      ).opacity(configuration.isPressed ? 0.8 : 1)
  }
}

/// The system share sheet, for an image file or a link.
struct ActivitySheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
