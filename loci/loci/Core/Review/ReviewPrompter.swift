import Foundation
import Observation

/// Decides when to ask for an App Store rating. iOS still decides whether the
/// sheet shows; this only keeps the ask to good moments and rare.
///
/// A success is a search finishing while the user looks at it. The ask comes
/// after the third, never in the first day after install, at most once every
/// 120 days, and never once the user has turned it off in Settings. Asking
/// resets the count.
@Observable @MainActor final class ReviewPrompter {
  static let shared = ReviewPrompter()

  static let successThreshold = 3
  static let firstSessionGrace: TimeInterval = 24 * 60 * 60
  static let cooldown: TimeInterval = 120 * 24 * 60 * 60
  /// Long enough for the finished-search flash (1.2s) to settle first.
  static let settleDelay: Duration = .seconds(1.5)

  private enum Key {
    static let firstSeenAt = "loci_review_first_seen_at"
    static let successCount = "loci_review_success_count"
    static let lastPromptAt = "loci_review_last_prompt_at"
    static let enabled = "loci_review_enabled"
  }

  /// Set by a success that earns the ask; the results screen observes it.
  private(set) var isPromptDue = false

  /// The Settings switch. Off clears any pending ask.
  var isEnabled: Bool {
    didSet {
      defaults.set(isEnabled, forKey: Key.enabled)
      if !isEnabled { isPromptDue = false }
    }
  }

  private let defaults: UserDefaults
  private let now: () -> Date

  init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
    self.defaults = defaults
    self.now = now
    self.isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
    if defaults.object(forKey: Key.firstSeenAt) == nil { defaults.set(now(), forKey: Key.firstSeenAt) }
  }

  func recordSuccess() {
    guard isEnabled else { return }
    let count = defaults.integer(forKey: Key.successCount) + 1
    defaults.set(count, forKey: Key.successCount)
    if count >= Self.successThreshold, isOutsideQuietPeriods { isPromptDue = true }
  }

  /// Call once the request has been handed to iOS.
  func didPrompt() {
    defaults.set(0, forKey: Key.successCount)
    defaults.set(now(), forKey: Key.lastPromptAt)
    isPromptDue = false
  }

  /// The screen went away before the ask. The count is kept, so the next
  /// success asks instead of an old result opened later.
  func skipPrompt() {
    isPromptDue = false
  }

  /// Past the first day, and past the cooldown since the last ask.
  private var isOutsideQuietPeriods: Bool {
    let current = now()
    let firstSeen = defaults.object(forKey: Key.firstSeenAt) as? Date ?? current
    guard current.timeIntervalSince(firstSeen) >= Self.firstSessionGrace else { return false }
    guard let last = defaults.object(forKey: Key.lastPromptAt) as? Date else { return true }
    return current.timeIntervalSince(last) >= Self.cooldown
  }
}
