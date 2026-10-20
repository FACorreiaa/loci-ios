import AppIntents

/// "Plan a day in Loci": Siri asks which city, then Discover opens with the
/// request in the composer, ready to send.
struct PlanDayIntent: AppIntent {
  static let title: LocalizedStringResource = "Plan a day"
  static let description: IntentDescription? = IntentDescription("Opens Loci with a day plan for a city ready to send.")
  static let openAppWhenRun = true

  @Parameter(title: "City", requestValueDialog: "Which city?")
  var city: String

  @MainActor func perform() async throws -> some IntentResult {
    AppRouter.shared.open(IntentRoute.url(for: .planDay(city: city)))
    return .result()
  }
}
