import AppIntents

/// "What's near me that I'd like in Loci": opens Near me.
struct NearbyFitsIntent: AppIntent {
  static let title: LocalizedStringResource = "What's near me that I'd like"
  static let description: IntentDescription? = IntentDescription("Opens Near me in Loci.")
  static let openAppWhenRun = true

  @MainActor func perform() async throws -> some IntentResult {
    AppRouter.shared.open(IntentRoute.url(for: .nearbyFits))
    return .result()
  }
}
