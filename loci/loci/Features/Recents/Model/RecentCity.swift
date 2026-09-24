import Foundation
import LociConnectProto
import SwiftProtobuf

/// One city of the Cities view, from `GetRecentInteractions{groupByCity: true}`
/// (web: components/features/Recents/CitiesView.tsx over `useRecentInteractions`).
///
/// Only what the server fills is kept. It sends the city name, a count, the
/// latest time and up to five prompts; `country` is always empty today, and
/// web's favourites, itineraries and places tabs have nothing behind them.
nonisolated struct RecentCity: Identifiable, Hashable, Sendable {
  var name: String
  var country: String
  var interactionCount: Int
  var lastActivity: Date?
  var interactions: [CityInteraction]

  var id: String { name }

  var level: CityActivityLevel { CityActivityLevel(count: interactionCount) }
}

/// One prompt in a city. It carries no session id, so it opens nothing.
nonisolated struct CityInteraction: Identifiable, Hashable, Sendable {
  var id: String
  var prompt: String
  /// "hotel", "restaurant", "poi" or "chat": what the answer held.
  var entityType: String
  var occurredAt: Date?

  var badge: ActivityBadge {
    switch entityType {
    case "hotel": ActivityBadge(systemImage: "bed.double", label: "Stays")
    case "restaurant": ActivityBadge(systemImage: "fork.knife", label: "Dining")
    case "poi": ActivityBadge(systemImage: "mappin.and.ellipse", label: "Places")
    default: ActivityBadge(systemImage: "bubble.left", label: "Chat")
    }
  }
}

/// Web's city badge: 10 and over is very active, 5 and over active, else visited.
nonisolated enum CityActivityLevel: Equatable, Sendable {
  case high, medium, low

  init(count: Int) {
    self = count >= 10 ? .high : count >= 5 ? .medium : .low
  }

  var label: String {
    switch self {
    case .high: "Very active"
    case .medium: "Active"
    case .low: "Visited"
    }
  }

  var systemImage: String {
    switch self {
    case .high: "flame"
    case .medium: "star"
    case .low: "mappin"
    }
  }
}

nonisolated enum RecentCities {
  /// Cities newest first. Ties (and cities with no time) fall back to the name,
  /// so two loads never swap equal rows (web's comparator has no tiebreak).
  static func cities(_ response: Loci_Recents_GetRecentInteractionsResponse) -> [RecentCity] {
    response.citySummaries.map(city).sorted { lhs, rhs in
      switch (lhs.lastActivity, rhs.lastActivity) {
      case let (left?, right?) where left != right: left > right
      case (.some, nil): true
      case (nil, .some): false
      default: lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
    }
  }

  static func city(_ summary: Loci_Recents_CityInteractionSummary) -> RecentCity {
    RecentCity(
      name: summary.cityName,
      country: summary.country,
      interactionCount: Int(summary.interactionCount),
      lastActivity: summary.hasLatestInteraction ? summary.latestInteraction.date : nil,
      interactions: summary.recentInteractions.map { interaction in
        CityInteraction(
          id: interaction.id,
          prompt: extractMessage(interaction.description_p, cityName: summary.cityName),
          entityType: interaction.entityType,
          occurredAt: interaction.hasCreatedAt ? interaction.createdAt.date : nil
        )
      }
    )
  }

  /// A readable line from a stored prompt (web: recents.ts `extractMessage`):
  /// unwrap the server's wrapper and name the city when the message does not;
  /// turn a POI lookup prompt into "Looking up X in Y"; else cut at 50 characters.
  /// Web appends the city whenever the message does not end with it, which
  /// doubles it after a full stop ("Itinerary in Funchal. Funchal"); here the
  /// city is added only when the message does not mention it at all.
  static func extractMessage(_ description: String, cityName: String) -> String {
    guard !description.isEmpty else { return cityName }
    let message = ActivityFeed.stripPromptWrapper(description)
    if message != description {
      guard !message.isEmpty else { return cityName }
      if cityName.isEmpty || message.localizedCaseInsensitiveContains(cityName) { return message }
      return "\(message) \(cityName)"
    }
    if description.hasPrefix("Return ONLY"), let match = description.firstMatch(of: /for "([^"]+)" in ([^.]+)/) {
      return "Looking up \(match.1) in \(match.2)"
    }
    return description.count > 50 ? "\(description.prefix(50))..." : description
  }

  /// Cities whose name contains the search.
  static func filter(_ cities: [RecentCity], query: String) -> [RecentCity] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return cities }
    return cities.filter { $0.name.localizedCaseInsensitiveContains(needle) }
  }
}
