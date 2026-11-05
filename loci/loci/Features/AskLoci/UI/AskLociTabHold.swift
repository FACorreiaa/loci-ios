import SwiftUI
import UIKit

/// A hold on the Assistant tab opens Ask Loci; a tap still opens the chat.
///
/// SwiftUI's `Tab` has no gesture of its own, so this finds the bar and adds a
/// long-press recognizer to it. Assistant is the third of five tabs. An iPhone's
/// bar is a `UITabBar`, where that is the centre fifth; a regular-width iPad shows
/// a floating bar at the top instead, whose items are the cells of a collection
/// view. Only public UIKit: if neither is found the app carries on with tap alone.
struct AskLociTabHold: UIViewRepresentable {
  let onHold: @MainActor () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onHold: onHold) }

  func makeUIView(context: Context) -> ProbeView {
    let view = ProbeView()
    view.coordinator = context.coordinator
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ uiView: ProbeView, context: Context) {}

  /// Sits behind the tab view, and looks for the bar once it is in a window and
  /// whenever the width class changes, since an iPad swaps bars when it does.
  final class ProbeView: UIView {
    weak var coordinator: Coordinator?

    override init(frame: CGRect) {
      super.init(frame: frame)
      registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (view: ProbeView, _) in
        view.coordinator?.attach(from: view)
      }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      coordinator?.attach(from: self)
    }
  }

  @MainActor
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    /// Long enough to stay out of a tap's way, short enough to feel immediate.
    static let holdDuration: TimeInterval = 0.4
    /// A finger that moves further than this is dragging between tabs.
    static let allowedMovement: CGFloat = 10
    private static let tabCount = 5
    private static let assistantIndex = 2
    /// A floating bar is a short strip near the top of the window; this keeps
    /// out any five-item carousel on the page beneath it.
    private static let floatingBarMaxHeight: CGFloat = 60
    private static let floatingBarMaxY: CGFloat = 120
    private static let attempts = 20

    private let onHold: @MainActor () -> Void
    /// The tab when the finger came down. A floating bar can select the tab it is
    /// pressing before the press becomes a hold, and a hold must not change tabs.
    private var tabAtTouchDown: AppRouter.Tab?
    private lazy var hold: UILongPressGestureRecognizer = {
      let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
      hold.minimumPressDuration = Self.holdDuration
      hold.allowableMovement = Self.allowedMovement
      hold.delegate = self
      // Taking the touch once it's a hold is what stops the tab being selected on release.
      hold.cancelsTouchesInView = true
      return hold
    }()

    init(onHold: @escaping @MainActor () -> Void) { self.onHold = onHold }

    /// Keeps looking for a few seconds: bars come and go during launch, and one
    /// that was there at first may not be the one left on screen.
    func attach(from view: UIView, attempt: Int = 0) {
      guard let window = view.window else { return }
      if let found = Self.floatingBar(in: window) ?? Self.tabBar(in: window), hold.view !== found {
        // Adding a recognizer to a new view takes it off the old one.
        found.addGestureRecognizer(hold)
      }
      guard attempt < Self.attempts else { return }
      Task { [weak self, weak view] in
        try? await Task.sleep(for: .milliseconds(250))
        if let self, let view { self.attach(from: view, attempt: attempt + 1) }
      }
    }

    private static func tabBar(in view: UIView) -> UITabBar? {
      if view.isHidden { return nil }
      if let bar = view as? UITabBar { return bar }
      for subview in view.subviews {
        if let bar = tabBar(in: subview) { return bar }
      }
      return nil
    }

    private static func floatingBar(in view: UIView) -> UICollectionView? {
      if view.isHidden { return nil }
      if let collection = view as? UICollectionView, isFloatingBar(collection) { return collection }
      for subview in view.subviews {
        if let bar = floatingBar(in: subview) { return bar }
      }
      return nil
    }

    private static func isFloatingBar(_ collection: UICollectionView) -> Bool {
      let frame = collection.convert(collection.bounds, to: nil)
      return frame.height <= floatingBarMaxHeight
        && frame.minY <= floatingBarMaxY
        && tabSection(of: collection) != nil
    }

    /// The bar keeps an empty section ahead of its tabs, so it isn't section 0.
    private static func tabSection(of collection: UICollectionView) -> Int? {
      (0..<collection.numberOfSections).first { collection.numberOfItems(inSection: $0) == tabCount }
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
      guard gesture.state == .began else { return }
      // Ends whatever the bar was tracking, which would otherwise select the tab.
      if let bar = gesture.view { Self.cancelTracking(in: bar, except: gesture) }
      if let tabAtTouchDown, AppRouter.shared.selectedTab != tabAtTouchDown {
        AppRouter.shared.selectedTab = tabAtTouchDown
      }
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      onHold()
    }

    private static func cancelTracking(in view: UIView, except kept: UIGestureRecognizer) {
      for recognizer in view.gestureRecognizers ?? [] where recognizer !== kept && recognizer.isEnabled {
        recognizer.isEnabled = false
        recognizer.isEnabled = true
      }
      for subview in view.subviews { cancelTracking(in: subview, except: kept) }
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      tabAtTouchDown = AppRouter.shared.selectedTab
      return true
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
      guard let bar = gesture.view else { return false }
      let location = gesture.location(in: bar)
      if let collection = bar as? UICollectionView {
        guard let section = Self.tabSection(of: collection) else { return false }
        let assistant = IndexPath(item: Self.assistantIndex, section: section)
        return collection.cellForItem(at: assistant)?.frame.contains(location) ?? false
      }
      let zone = bar.bounds.width / CGFloat(Self.tabCount)
      return location.x >= zone * CGFloat(Self.assistantIndex) && location.x <= zone * CGFloat(Self.assistantIndex + 1)
    }

    func gestureRecognizer(
      _ gesture: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
}
