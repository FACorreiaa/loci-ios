import Foundation

/// Offline sample data for `-designPreview recents`, `recentsCities` and
/// `recentCity`, and for the SwiftUI previews. Times are relative to now so the
/// day headings always show all four groups.
nonisolated struct PreviewRecentsService: RecentsService {
  func activity(userId: String, pages: Int) async throws -> ActivityPage {
    ActivityPage(entries: ActivityEntry.previewFeed, hasMore: true)
  }

  func cities(userId: String) async throws -> [RecentCity] { RecentCity.previewCities }
}

nonisolated extension ActivityEntry {
  static var previewFeed: [ActivityEntry] {
    let now = Date()
    func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
    func entry(_ id: String, _ kind: ActivityKind, _ detail: String, _ label: String, _ city: String, _ hours: Double) -> ActivityEntry {
      ActivityEntry(id: id, kind: kind, detail: detail, label: label, cityName: city, refId: "session-\(id)", occurredAt: ago(hours))
    }
    return [
      entry("1", .prompt, "itinerary", "3 days in Lisbon with kids, nothing too hilly", "Lisbon", 0.3),
      entry("2", .favourite, "poi", "Miradouro da Senhora do Monte", "Lisbon", 1.2),
      entry("3", .prompt, "dining", "Seafood in Cascais that locals go to", "Cascais", 2.5),
      entry("4", .savedItinerary, "itinerary", "A slow weekend in Porto", "Porto", 26),
      entry("5", .prompt, "accommodation", "Quiet boutique hotel near Ribeira", "Porto", 28),
      entry("6", .prompt, "nearby", "What's good near me right now?", "", 30),
      entry("7", .prompt, "activities", "Rainy-day things to do in Sintra", "Sintra", 72),
      entry("8", .prompt, "general", "Is Évora worth a day trip in August?", "Évora", 96),
      entry("9", .favourite, "restaurant", "Taberna da Rua das Flores", "Lisbon", 24 * 12),
    ]
  }
}

nonisolated extension RecentCity {
  private static func asked(_ id: String, _ prompt: String, _ entityType: String, hoursAgo: Double) -> CityInteraction {
    CityInteraction(id: id, prompt: prompt, entityType: entityType, occurredAt: Date().addingTimeInterval(-hoursAgo * 3600))
  }

  static var previewLisbon: RecentCity {
    RecentCity(
      name: "Lisbon",
      country: "",
      interactionCount: 5,
      lastActivity: Date().addingTimeInterval(-1200),
      interactions: [
        asked("l1", "3 days in Lisbon with kids, nothing too hilly", "poi", hoursAgo: 0.33),
        asked("l2", "Where to eat bacalhau in Alfama", "restaurant", hoursAgo: 2),
        asked("l3", "A hotel with a view in Graça", "hotel", hoursAgo: 24),
        asked("l4", "Is the 28 tram worth the queue?", "chat", hoursAgo: 48),
        asked("l5", "Looking up Oceanário in Lisbon", "poi", hoursAgo: 120),
      ]
    )
  }

  static var previewCities: [RecentCity] {
    [
      previewLisbon,
      RecentCity(
        name: "Porto",
        country: "",
        interactionCount: 2,
        lastActivity: Date().addingTimeInterval(-86_400),
        interactions: [asked("p1", "Quiet boutique hotel near Ribeira", "hotel", hoursAgo: 24)]
      ),
      RecentCity(
        name: "Sintra",
        country: "",
        interactionCount: 1,
        lastActivity: Date().addingTimeInterval(-86_400 * 3),
        interactions: [asked("s1", "Rainy-day things to do in Sintra", "poi", hoursAgo: 72)]
      ),
    ]
  }
}
