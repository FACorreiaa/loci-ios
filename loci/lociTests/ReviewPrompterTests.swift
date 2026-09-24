import Foundation
import Testing

@testable import loci

/// The rating ask comes after the third watched success, never on day one,
/// at most every 120 days, and never once switched off.
@MainActor struct ReviewPrompterTests {
  private let installed = Date(timeIntervalSince1970: 1_800_000_000)
  private let day: TimeInterval = 24 * 60 * 60

  /// A prompter on its own defaults suite, with a clock the test moves.
  private func prompter(clock: TestClock) throws -> ReviewPrompter {
    let suite = "ReviewPrompterTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return ReviewPrompter(defaults: defaults, now: { clock.now })
  }

  private func record(_ times: Int, on prompter: ReviewPrompter) {
    for _ in 0..<times { prompter.recordSuccess() }
  }

  @Test func asksOnTheThirdSuccess() throws {
    let clock = TestClock(installed)
    let reviews = try prompter(clock: clock)
    clock.now = installed.addingTimeInterval(2 * day)
    record(2, on: reviews)
    #expect(!reviews.isPromptDue)
    reviews.recordSuccess()
    #expect(reviews.isPromptDue)
  }

  @Test func neverAsksInTheFirstDay() throws {
    let clock = TestClock(installed)
    let reviews = try prompter(clock: clock)
    clock.now = installed.addingTimeInterval(day - 60)
    record(5, on: reviews)
    #expect(!reviews.isPromptDue)
    // Successes from day one still count once the day has passed.
    clock.now = installed.addingTimeInterval(day)
    reviews.recordSuccess()
    #expect(reviews.isPromptDue)
  }

  @Test func waitsOneHundredTwentyDaysBetweenAsks() throws {
    let clock = TestClock(installed)
    let reviews = try prompter(clock: clock)
    clock.now = installed.addingTimeInterval(2 * day)
    record(3, on: reviews)
    reviews.didPrompt()
    clock.now = clock.now.addingTimeInterval(119 * day)
    record(3, on: reviews)
    #expect(!reviews.isPromptDue)
    clock.now = clock.now.addingTimeInterval(day)
    reviews.recordSuccess()
    #expect(reviews.isPromptDue)
  }

  @Test func askingResetsTheCount() throws {
    let clock = TestClock(installed)
    let reviews = try prompter(clock: clock)
    clock.now = installed.addingTimeInterval(2 * day)
    record(3, on: reviews)
    reviews.didPrompt()
    #expect(!reviews.isPromptDue)
    clock.now = clock.now.addingTimeInterval(121 * day)
    record(2, on: reviews)
    #expect(!reviews.isPromptDue)
    reviews.recordSuccess()
    #expect(reviews.isPromptDue)
  }

  @Test func switchedOffNeverAsks() throws {
    let clock = TestClock(installed)
    let reviews = try prompter(clock: clock)
    #expect(reviews.isEnabled)
    clock.now = installed.addingTimeInterval(2 * day)
    record(2, on: reviews)
    reviews.isEnabled = false
    record(3, on: reviews)
    #expect(!reviews.isPromptDue)
  }

  @Test func switchingOffDropsAPendingAsk() throws {
    let clock = TestClock(installed)
    let reviews = try prompter(clock: clock)
    clock.now = installed.addingTimeInterval(2 * day)
    record(3, on: reviews)
    reviews.isEnabled = false
    #expect(!reviews.isPromptDue)
  }

  @Test func switchIsRememberedAcrossLaunches() throws {
    let suite = "ReviewPrompterTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    ReviewPrompter(defaults: defaults).isEnabled = false
    #expect(!ReviewPrompter(defaults: defaults).isEnabled)
  }

  @Test func skippedAskComesBackOnTheNextSuccess() throws {
    let clock = TestClock(installed)
    let reviews = try prompter(clock: clock)
    clock.now = installed.addingTimeInterval(2 * day)
    record(3, on: reviews)
    reviews.skipPrompt()
    #expect(!reviews.isPromptDue)
    reviews.recordSuccess()
    #expect(reviews.isPromptDue)
  }
}

/// A clock the test sets by hand.
private final class TestClock {
  var now: Date

  init(_ now: Date) { self.now = now }
}
