import SwiftUI
import UIKit

extension View {
  /// Keep the edge swipe back working on a pushed page that hides the
  /// navigation bar (the Muse chat). UIKit's own delegate refuses the gesture
  /// while the bar is hidden; this hands it one that allows it whenever there
  /// is a page to go back to. Checked by MuseChatNavigationUITests.
  func interactivePopEnabled() -> some View {
    background { InteractivePop().frame(width: 0, height: 0).accessibilityHidden(true) }
  }
}

/// Named for the file: the enabler the `interactivePopEnabled()` modifier installs.
private struct InteractivePop: UIViewRepresentable {
  func makeUIView(context: Context) -> Probe { Probe() }
  func updateUIView(_ probe: Probe, context: Context) { probe.enable() }

  /// A zero-size view that finds the navigation controller it sits in once it is on screen.
  final class Probe: UIView {
    override func didMoveToWindow() {
      super.didMoveToWindow()
      enable()
      // SwiftUI finishes the push after the view joins the window; check again once it has.
      DispatchQueue.main.async { [weak self] in self?.enable() }
    }

    func enable() {
      guard window != nil, let navigation = navigationController else { return }
      PopGestureDelegate.shared.attach(to: navigation)
    }

    private var navigationController: UINavigationController? {
      var responder: UIResponder? = self
      while let next = responder?.next {
        if let navigation = next as? UINavigationController { return navigation }
        if let controller = next as? UIViewController, let navigation = controller.navigationController { return navigation }
        responder = next
      }
      return nil
    }
  }
}

/// One delegate for every stack: the gesture holds its delegate weakly, so it lives here.
/// Pages that show the bar keep UIKit's own answer; only a hidden bar gets the override.
@MainActor private final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
  static let shared = PopGestureDelegate()
  /// Each stack's own delegate, kept strongly so UIKit's answer is still there to ask.
  private let original = NSMapTable<UINavigationController, AnyObject>.weakToStrongObjects()

  func attach(to navigation: UINavigationController) {
    guard let gesture = navigation.interactivePopGestureRecognizer else { return }
    if gesture.delegate !== self {
      if let existing = gesture.delegate { original.setObject(existing, forKey: navigation) }
      gesture.delegate = self
    }
    gesture.isEnabled = true
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let navigation = gestureRecognizer.view?.next as? UINavigationController
      ?? original.keyEnumerator().allObjects.lazy.compactMap({ $0 as? UINavigationController })
        .first(where: { $0.interactivePopGestureRecognizer === gestureRecognizer })
    else { return false }
    if !navigation.isNavigationBarHidden, let uikit = original.object(forKey: navigation) as? UIGestureRecognizerDelegate {
      return uikit.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
    }
    // Never mid-transition, and only with somewhere to go back to.
    return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
  }
}
