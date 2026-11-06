import XCTest

/// Ask Loci with answers on screen: the panel must leave its header and the
/// backdrop reachable, keyboard up or down. A typed question keeps the keyboard
/// up, and a panel sized to the window pushed Close off the top of the screen.
final class AskLociOverlayUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor private func launch() throws -> XCUIApplication {
    let app = XCUIApplication()
    // `-designPreview` screens exist only in Debug builds.
    app.launchArguments = ["-designPreview", "askLociCards"]
    app.launch()
    guard app.textFields["Ask anything"].waitForExistence(timeout: 15) else {
      throw XCTSkip("Design previews need a Debug build")
    }
    return app
  }

  private func shot(_ name: String, _ app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor func testCloseStaysReachableWithKeyboardUp() throws {
    let app = try launch()
    let field = app.textFields["Ask anything"]
    field.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "The keyboard did not come up")
    shot("keyboard-up", app)

    XCTAssertTrue(app.buttons["Close"].isHittable, "Close is off screen with the keyboard up")
    app.buttons["Close"].tap()
    XCTAssertFalse(field.waitForExistence(timeout: 1), "Close did not close Ask Loci")
  }

  /// The panel leaves a strip of backdrop above it, and a tap there closes it.
  @MainActor func testTapAboveThePanelCloses() throws {
    let app = try launch()
    let field = app.textFields["Ask anything"]
    field.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "The keyboard did not come up")

    // Just under the status bar: backdrop, not panel.
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    XCTAssertFalse(field.waitForExistence(timeout: 1), "A tap above the panel did not close Ask Loci")
  }

  @MainActor func testCloseStaysReachableAfterATypedQuestion() throws {
    let app = try launch()
    let field = app.textFields["Ask anything"]
    field.tap()
    field.typeText("check my highlights")
    // Send, not Return: the field is multi-line, so Return adds a line.
    // The panel's button, not the keyboard's Send key.
    app.windows.firstMatch.buttons.matching(NSPredicate(format: "label == 'Send'")).firstMatch.tap()
    XCTAssertTrue(app.staticTexts["check my highlights"].waitForExistence(timeout: 3), "The question was not sent")
    shot("typed-submit", app)

    XCTAssertTrue(app.buttons["Close"].isHittable, "Close is off screen after a typed question")
  }
}
