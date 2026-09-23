import XCTest

/// The Muse chat hides the navigation bar on a pushed results page. The
/// edge swipe back must still work, since the header's chevron is the only
/// other way out.
final class MuseChatNavigationUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor func testEdgeSwipeGoesBackWithTheBarHidden() throws {
    try swipeBack(preview: "museChatPush")
  }

  /// The control: proves the synthesized swipe is a real back gesture.
  @MainActor func testEdgeSwipeGoesBackWithTheBarShowing() throws {
    try swipeBack(preview: "museChatPushBar")
  }

  @MainActor private func swipeBack(preview: String) throws {
    let app = XCUIApplication()
    // `-designPreview` screens exist only in Debug builds.
    app.launchArguments = ["-designPreview", preview]
    app.launch()

    let open = app.buttons["Open the chat"]
    guard open.waitForExistence(timeout: 10) else { throw XCTSkip("Design previews need a Debug build.") }
    open.tap()

    let newChat = app.buttons["New chat"]
    XCTAssertTrue(newChat.waitForExistence(timeout: 5), "The Muse chat did not open")

    let window = app.windows.firstMatch
    let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
    let middle = window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
    edge.press(forDuration: 0.05, thenDragTo: middle, withVelocity: .fast, thenHoldForDuration: 0.05)

    XCTAssertTrue(newChat.waitForNonExistence(timeout: 5), "Swiping from the left edge did not go back")
    XCTAssertTrue(open.isHittable)
  }
}
