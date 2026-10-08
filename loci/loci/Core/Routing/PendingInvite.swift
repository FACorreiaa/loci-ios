import Foundation

/// The code from an invite link opened on this device, kept until the next
/// sign-up sends it, so the server can record who invited the new account.
///
/// Stored, not held in memory: the link usually arrives signed out, often on
/// a cold start, and sign-up can come several screens (or a relaunch) later.
/// Cleared after any successful sign-in or sign-up, whether or not it applied;
/// a stale one expires after 30 days.
enum PendingInvite {
  private static let codeKey = "pendingInvite.code"
  private static let savedAtKey = "pendingInvite.savedAt"
  static let lifetime: TimeInterval = 30 * 24 * 60 * 60
  static let maxCodeLength = 64

  static func remember(_ code: String, defaults: UserDefaults = .standard, now: Date = .now) {
    guard !code.isEmpty, code.count <= maxCodeLength else { return }
    defaults.set(code, forKey: codeKey)
    defaults.set(now.timeIntervalSince1970, forKey: savedAtKey)
  }

  /// The waiting code, or nil when there is none or it has gone stale.
  static func code(defaults: UserDefaults = .standard, now: Date = .now) -> String? {
    guard let code = defaults.string(forKey: codeKey) else { return nil }
    let savedAt = Date(timeIntervalSince1970: defaults.double(forKey: savedAtKey))
    guard now.timeIntervalSince(savedAt) <= lifetime else {
      clear(defaults: defaults)
      return nil
    }
    return code
  }

  static func clear(defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: codeKey)
    defaults.removeObject(forKey: savedAtKey)
  }
}
