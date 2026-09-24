import Foundation
import PostHog

/// Product analytics, kept behind one typed seam (web: src/lib/analytics.ts).
///
/// Event names are shared with web on purpose: the funnel is one dataset, and
/// an iOS signup must count in the same "strangers" number as a web one.
/// Adding a case here is a deliberate act — an event nobody reads is noise.
enum AnalyticsEvent: String {
  /// A stranger finished sign-up. Metric: stranger signups.
  case signupCompleted = "signup_completed"
  /// A search reached COMPLETE. Metric: finished first itinerary (first per person, in PostHog).
  case itineraryFinished = "itinerary_finished"
}

@MainActor enum Analytics {
  private static var isActive = false

  /// Start analytics. Debug builds stay silent: AppConfig carries a fallback
  /// token, and simulator runs would otherwise land in the launch funnel.
  static func start(config: AppConfig = .shared) {
    guard !isActive, config.environment != .local, !config.postHogProjectToken.isEmpty else { return }
    let options = PostHogConfig(projectToken: config.postHogProjectToken, host: config.postHogHost)
    // UIKit screen names here are hosting controllers, not screens anyone would read.
    options.captureScreenViews = false
    PostHogSDK.shared.setup(options)
    isActive = true
  }

  static func capture(_ event: AnalyticsEvent, _ properties: [String: Any]? = nil) {
    guard isActive else { return }
    PostHogSDK.shared.capture(event.rawValue, properties: properties)
  }

  /// A screen was shown (PostHog `$screen`; web gets `$pageview` for free).
  /// Automatic screen capture is off, so each screen names itself.
  static func screen(_ name: String, _ properties: [String: Any]? = nil) {
    guard isActive else { return }
    PostHogSDK.shared.screen(name, properties: properties)
  }

  /// Attach later events to the server-issued user id, as web does on sign-in.
  static func identify(userId: String?, username: String? = nil) {
    guard isActive, let userId, !userId.isEmpty else { return }
    var properties: [String: Any] = [:]
    if let username, !username.isEmpty { properties["username"] = username }
    PostHogSDK.shared.identify(userId, userProperties: properties)
  }

  /// Forget the current user on sign-out so two people on one phone do not merge.
  static func reset() {
    guard isActive else { return }
    PostHogSDK.shared.reset()
  }
}
