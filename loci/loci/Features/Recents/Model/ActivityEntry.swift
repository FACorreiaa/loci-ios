import Foundation
import LociConnectProto
import SwiftProtobuf

/// Which table a feed row came from (web: lib/recents/types.ts `ActivityKind`).
/// The server puts it in `metadata["kind"]`; a kind this build does not know is
/// `.other`, shown but not tappable.
nonisolated enum ActivityKind: String, Sendable, Hashable {
  case prompt
  case savedItinerary = "saved_itinerary"
  case favourite
  case other
}

/// One row of the recents feed: one thing the person did, whichever table it
/// came from (web: `ActivityEntry`).
nonisolated struct ActivityEntry: Identifiable, Hashable, Sendable {
  var id: String
  var kind: ActivityKind
  /// The routed domain for a prompt, the content type for a favourite, "itinerary" for a save.
  var detail: String
  /// What the person typed, or the title of the thing they kept.
  var label: String
  var cityName: String
  /// The chat session id for a prompt or a saved itinerary, the item id for a favourite.
  var refId: String
  /// Nil when the server sent no timestamp. Web stamps those "now", which files
  /// an undated row under Today; here it goes under Earlier with no time.
  var occurredAt: Date?
}

/// One page of the feed, pages accumulated: web asks for `40 × pages` from offset 0.
nonisolated struct ActivityPage: Equatable, Sendable {
  var entries: [ActivityEntry]
  var hasMore: Bool
}

nonisolated enum ActivityFeed {
  static let pageSize = 40
  /// `GetInteractionHistoryRequest.limit` is `lte: 200` in the proto.
  static let maxLimit = 200

  /// The limit for `pages` accumulated pages, capped at what the server accepts.
  static func limit(pages: Int) -> Int { min(pageSize * max(pages, 1), maxLimit) }

  /// Map one proto interaction onto a feed entry (web: lib/api/recents.ts `mapActivityEntry`).
  /// `metadata.kind` is the discriminator; `entityType` carries the routed domain
  /// for a prompt, and `metadata.content_type` narrows a favourite.
  static func entry(_ interaction: Loci_Recents_RecentInteraction) -> ActivityEntry {
    let rawKind = interaction.metadata["kind"] ?? ""
    let kind = rawKind.isEmpty ? .prompt : (ActivityKind(rawValue: rawKind) ?? .other)
    let detail: String
    switch kind {
    case .favourite: detail = nonEmpty(interaction.metadata["content_type"]) ?? "poi"
    case .savedItinerary: detail = "itinerary"
    case .prompt, .other: detail = nonEmpty(interaction.entityType) ?? "general"
    }
    return ActivityEntry(
      id: interaction.id,
      kind: kind,
      detail: detail,
      // The server already unwraps the prompt; a second pass keeps an older server readable.
      label: stripPromptWrapper(interaction.description_p),
      cityName: interaction.cityName,
      refId: interaction.entityID,
      occurredAt: interaction.hasCreatedAt ? interaction.createdAt.date : nil
    )
  }

  /// A page from the response. `total_count` is a floor, not a total: the server
  /// reports one more than it served when another page exists. A feed already at
  /// the server's largest limit cannot grow, so it has no more to load.
  static func page(_ response: Loci_Recents_GetInteractionHistoryResponse, limit: Int) -> ActivityPage {
    let entries = response.interactions.map(entry)
    let hasMore = entries.count < Int(response.totalCount) && limit < maxLimit
    return ActivityPage(entries: entries, hasMore: hasMore)
  }

  /// The server stores the user turn as the prompt it assembled for the model:
  /// "Unified Chat Stream - Domain: itinerary, Message: Itinerary in Funchal."
  /// Anchored at both ends, so a message that merely mentions the wrapper is left
  /// alone (web: lib/api/prompt-wrapper.ts).
  static func stripPromptWrapper(_ text: String) -> String {
    guard let match = text.wholeMatch(of: /(?i)Unified Chat Stream - Domain:\s*\w+,\s*Message:\s*([\s\S]+)/) else { return text }
    return String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
  }
}

// MARK: - Type chips

/// A chip is a (kind, detail) pair: "Itineraries" means itinerary searches,
/// "Saved" means kept trips, and neither returns the other
/// (web: components/features/Recents/ActivityTypeChips.tsx).
nonisolated struct ActivityTypeOption: Identifiable, Hashable, Sendable {
  let id: String
  let label: String
  var kind: ActivityKind?
  var detail: String?

  static let all: [ActivityTypeOption] = [
    ActivityTypeOption(id: "all", label: "All"),
    ActivityTypeOption(id: "chat", label: "Chats", kind: .prompt, detail: "general"),
    ActivityTypeOption(id: "itinerary", label: "Itineraries", kind: .prompt, detail: "itinerary"),
    ActivityTypeOption(id: "activities", label: "Activities", kind: .prompt, detail: "activities"),
    ActivityTypeOption(id: "dining", label: "Dining", kind: .prompt, detail: "dining"),
    ActivityTypeOption(id: "accommodation", label: "Stays", kind: .prompt, detail: "accommodation"),
    ActivityTypeOption(id: "nearby", label: "Nearby", kind: .prompt, detail: "nearby"),
    ActivityTypeOption(id: "saved", label: "Saved", kind: .savedItinerary),
    ActivityTypeOption(id: "favourite", label: "Favourites", kind: .favourite),
  ]

  func matches(_ entry: ActivityEntry) -> Bool {
    if let kind, entry.kind != kind { return false }
    if let detail, entry.detail != detail { return false }
    return true
  }
}

nonisolated enum ActivityFilter {
  /// Per-chip counts over what has loaded, so an empty chip reads as empty. "All" has none.
  static func counts(_ entries: [ActivityEntry]) -> [String: Int] {
    var out: [String: Int] = [:]
    for option in ActivityTypeOption.all where option.id != "all" {
      out[option.id] = entries.filter(option.matches).count
    }
    return out
  }

  /// The chips and the search narrow what has loaded; the server is never sent
  /// an `InteractionFilter` (its validation rejects a filter that narrows by type only).
  static func apply(_ entries: [ActivityEntry], typeId: String, query: String) -> [ActivityEntry] {
    let option = ActivityTypeOption.all.first { $0.id == typeId }
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return entries.filter { entry in
      if let option, !option.matches(entry) { return false }
      guard !needle.isEmpty else { return true }
      return entry.label.localizedCaseInsensitiveContains(needle) || entry.cityName.localizedCaseInsensitiveContains(needle)
    }
  }
}

// MARK: - Badge

/// The icon and the word a row shows, so "seafood in Cascais" and "three days in
/// Porto" do not look alike (web: ActivityRow `descriptorFor`).
nonisolated struct ActivityBadge: Equatable, Sendable {
  let systemImage: String
  let label: String

  init(systemImage: String, label: String) {
    self.systemImage = systemImage
    self.label = label
  }

  init(_ entry: ActivityEntry) {
    switch entry.kind {
    case .savedItinerary: self.init(systemImage: "bookmark", label: "Saved")
    case .favourite: self.init(systemImage: "star", label: "Favourite")
    case .prompt, .other:
      switch entry.detail {
      case "general": self.init(systemImage: "bubble.left", label: "Chat")
      case "itinerary": self.init(systemImage: "map", label: "Itinerary")
      case "activities": self.init(systemImage: "ticket", label: "Activities")
      case "dining": self.init(systemImage: "fork.knife", label: "Dining")
      case "accommodation": self.init(systemImage: "bed.double", label: "Stays")
      case "nearby": self.init(systemImage: "location", label: "Nearby")
      default: self.init(systemImage: "magnifyingglass", label: "Search")
      }
    }
  }
}
