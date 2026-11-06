import XCTest

/// The search box is multi-line, and Return in a multi-line field adds a line
/// unless something catches it. Its key reads "send", so Return must send.
final class SearchComposerUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor private func launch() throws -> XCUIApplication {
    let app = XCUIApplication()
    // The real tabs, signed out. `-designPreview` screens exist only in Debug builds.
    app.launchArguments = ["-designPreview", "askLociTabs"]
    app.launch()
    let assistant = app.buttons.matching(identifier: "Assistant").allElementsBoundByIndex
    guard let tab = assistant.first(where: \.isHittable) ?? assistant.first, tab.waitForExistence(timeout: 15) else {
      throw XCTSkip("Design previews need a Debug build, or this layout has no Assistant tab button")
    }
    tab.tap()
    return app
  }

  @MainActor func testReturnSends() throws {
    let app = try launch()
    let field = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'Ask Loci'")).firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5), "No search box on the Assistant tab")
    field.tap()
    field.typeText("3 days in Lisbon\n")

    // Signed out, a send ends in an alert (no travel profile, or the server
    // turning the request away). Either way the search was started.
    let alert = app.alerts.firstMatch
    XCTAssertTrue(alert.waitForExistence(timeout: 10), "Return did not send the search")
    alert.buttons.firstMatch.tap()

    // With text in it the box has no placeholder to find it by; it is the tab's only field.
    let box = app.textFields.firstMatch
    XCTAssertTrue(box.waitForExistence(timeout: 3))
    XCTAssertFalse((box.value as? String ?? "").contains("\n"), "Return added a line to the search box")
  }
}
