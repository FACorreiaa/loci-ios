import AppIntents

/// The phrases Siri and Spotlight offer without any setup.
struct LociShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: PlanDayIntent(), phrases: ["Plan a day in \(.applicationName)"], shortTitle: "Plan a day", systemImageName: "map")
    AppShortcut(
      intent: NearbyFitsIntent(),
      phrases: ["What's near me that I'd like in \(.applicationName)"],
      shortTitle: "Near me",
      systemImageName: "location"
    )
  }
}
