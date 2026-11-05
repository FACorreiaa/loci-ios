import XCTest

/// A hold on the Assistant tab opens Ask Loci; a tap still opens the chat. Both
/// run on the real tab bar, since the hold is a recognizer added to it.
final class AskLociHoldUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor private func launch() throws -> XCUIApplication {
    let app = XCUIApplication()
    // `-designPreview` screens exist only in Debug builds.
    app.launchArguments = ["-designPreview", "askLociTabs"]
    app.launch()
    guard app.buttons["Assistant"].firstMatch.waitForExistence(timeout: 15) else {
      throw XCTSkip("Design previews need a Debug build, or this layout has no Assistant tab button")
    }
    return app
  }

  /// The tab as the person sees it. An iPad's accessibility tree also holds the
  /// bar it doesn't show, so the name alone matches twice.
  @MainActor private func tab(_ name: String, in app: XCUIApplication) -> XCUIElement {
    let matches = app.buttons.matching(identifier: name).allElementsBoundByIndex
    return matches.first(where: \.isHittable) ?? matches[0]
  }

  private func shot(_ name: String, _ app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor func testHoldOpensAskLociWithoutLeavingTheTab() throws {
    let app = try launch()
    tab("Saved", in: app).tap()
    XCTAssertTrue(tab("Saved", in: app).isSelected)

    tab("Assistant", in: app).press(forDuration: 0.8)

    XCTAssertTrue(app.textFields["Ask anything"].waitForExistence(timeout: 3), "The hold did not open Ask Loci")
    shot("hold-open", app)
    app.buttons["Close"].tap()
    XCTAssertFalse(app.textFields["Ask anything"].waitForExistence(timeout: 1))
    shot("hold-closed", app)
    XCTAssertTrue(tab("Saved", in: app).isSelected, "The hold changed the selected tab")
  }

  @MainActor func testTapStillOpensTheChat() throws {
    let app = try launch()
    tab("Assistant", in: app).tap()
    XCTAssertTrue(tab("Assistant", in: app).isSelected)
    XCTAssertFalse(app.textFields["Ask anything"].exists, "A tap opened Ask Loci")
  }

  @MainActor func testHoldOnAnotherTabDoesNothing() throws {
    let app = try launch()
    tab("Saved", in: app).press(forDuration: 0.8)
    XCTAssertFalse(app.textFields["Ask anything"].waitForExistence(timeout: 1), "A hold on Saved opened Ask Loci")
  }

  @MainActor func testShortPressStaysATap() throws {
    let app = try launch()
    tab("Assistant", in: app).press(forDuration: 0.1)
    XCTAssertFalse(app.textFields["Ask anything"].waitForExistence(timeout: 1))
    XCTAssertTrue(tab("Assistant", in: app).isSelected)
  }
}
