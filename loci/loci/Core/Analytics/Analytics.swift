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
  /// A place went into a list (`surface: "list"`, `content_type`), as web's
  /// useAddToListMutation sends it. Metric: saves per active user.
  case poiSaved = "poi_saved"
  /// A City Pack's page loaded ({slug}). Web has no equivalent yet.
  case packViewed = "pack_viewed"
  /// A pack was opened as the caller's own trip ({slug}). Web has no equivalent yet.
  case packClaimed = "pack_claimed"
  /// A review was posted or edited (`rating`, `is_edit`); web sends the same
  /// name from its reviews page. Metric: contributions per active user.
  case reviewSubmitted = "review_submitted"
  /// A trip export reached the share sheet. Properties: format (ics|pdf|markdown), day_count.
  case tripExported = "trip_exported"
  /// ShareTrip returned a public link. Properties: content_type ("trip").
  case shareLinkCreated = "share_link_created"
  /// A field report was filed (`field` as the proto enum name, `status`,
  /// `poiId`, `answers`), as web's ClaimForm sends it. Metric: contributions per active user.
  case placeClaimSubmitted = "place_claim_submitted"
  /// A missing place was proposed (`city`), as web's AddPlaceForm sends it.
  case placeSubmitted = "place_submitted"
  /// The first-run questionnaire closed: saved the default travel profile
  /// (`skipped: false`) or was skipped (`skipped: true`), with the `step` it
  /// closed on (budget, pace, getting_around, interests).
  case onboardingCompleted = "onboarding_completed"
  /// A place went into a trip from its detail (`source: "place_detail"`, and
  /// `new_trip` when it started one). Web's AddToTripButton sends nothing yet.
  case tripStopAdded = "trip_stop_added"
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
