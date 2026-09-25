import Foundation
import LociConnectProto

/// The first-run profile wizard's rules (web: lib/trip-setup.ts): four
/// questions become one default travel profile, sent as the server expects
/// it — catalogue ids for interests, real pace and transport enums — and
/// offered once, to an account that has no profile yet.
nonisolated enum TripSetup {
  struct Interest: Equatable, Sendable {
    let id: String
    let name: String
  }

  enum Budget: Int, CaseIterable, Identifiable, Sendable {
    case shoestring = 1, balanced, comfortable, luxury

    var id: Int { rawValue }
    var label: String {
      switch self {
      case .shoestring: "Shoestring"
      case .balanced: "Balanced"
      case .comfortable: "Comfortable"
      case .luxury: "Luxury"
      }
    }
    var hint: String {
      switch self {
      case .shoestring: "Free & cheap picks"
      case .balanced: "Mix of value & treats"
      case .comfortable: "Lean into quality"
      case .luxury: "Best of everything"
      }
    }
    var symbol: String {
      switch self {
      case .shoestring: "backpack"
      case .balanced: "scalemass"
      case .comfortable: "sparkles"
      case .luxury: "crown"
      }
    }
  }

  enum Pace: String, CaseIterable, Identifiable, Sendable {
    case relaxed, moderate, packed

    var id: String { rawValue }
    var label: String {
      switch self {
      case .relaxed: "Relaxed"
      case .moderate: "Moderate"
      case .packed: "Packed"
      }
    }
    var hint: String {
      switch self {
      case .relaxed: "A few things, unhurried"
      case .moderate: "A comfortable rhythm"
      case .packed: "See as much as possible"
      }
    }
    var symbol: String {
      switch self {
      case .relaxed: "leaf"
      case .moderate: "figure.walk"
      case .packed: "bolt"
      }
    }
    /// "packed" is the server's FAST; web used to send the label and get ANY.
    var proto: Loci_Profile_SearchPace {
      switch self {
      case .relaxed: .relaxed
      case .moderate: .moderate
      case .packed: .fast
      }
    }
  }

  enum Mobility: String, CaseIterable, Identifiable, Sendable {
    case walking, transit, car, wheelchair

    var id: String { rawValue }
    var label: String {
      switch self {
      case .walking: "On foot"
      case .transit: "Public transit"
      case .car: "By car"
      case .wheelchair: "Step-free / accessible"
      }
    }
    var symbol: String {
      switch self {
      case .walking: "figure.walk"
      case .transit: "tram"
      case .car: "car"
      case .wheelchair: "figure.roll"
      }
    }
    /// Step-free travel is walking plus the accessible flag; the enum has no case for it.
    var proto: Loci_Profile_TransportPreference {
      switch self {
      case .walking, .wheelchair: .walk
      case .transit: .public
      case .car: .car
      }
    }
  }

  /// Curated chips, matched against the interest catalogue by name.
  static let curatedInterests = [
    "Food & Dining", "Art & Culture", "History", "Nature & Parks", "Nightlife", "Shopping",
    "Architecture", "Photography", "Local Culture", "Adventure", "Relaxation", "Family",
  ]

  struct Answers: Equatable, Sendable {
    var budget: Int = Budget.balanced.rawValue
    var pace: Pace = .moderate
    var mobility: Mobility = .walking
    var interests: [String] = []
  }

  /// Catalogue ids for the chosen labels, in chip order; labels the catalogue lacks are dropped.
  static func interestIDs(for labels: [String], catalogue: [Interest]) -> [String] {
    var byName: [String: String] = [:]
    for interest in catalogue where byName[key(interest.name)] == nil { byName[key(interest.name)] = interest.id }
    var out: [String] = []
    for label in labels {
      if let id = byName[key(label)], !out.contains(id) { out.append(id) }
    }
    return out
  }

  /// The curated labels the catalogue has; when none match, the catalogue's own names (first 12).
  static func chips(catalogue: [Interest]) -> [String] {
    let names = Set(catalogue.map { key($0.name) })
    let curated = curatedInterests.filter { names.contains(key($0)) }
    if !curated.isEmpty { return curated }
    return Array(catalogue.map(\.name).prefix(12))
  }

  /// The default profile the first search will read, in the editor's own draft type
  /// (main-actor, like the editor that owns it).
  @MainActor static func draft(_ answers: Answers, catalogue: [Interest]) -> TravelProfileDraft {
    var draft = TravelProfileDraft(isDefault: true)
    draft.name = "My Trip Profile"
    draft.budgetLevel = Budget(rawValue: answers.budget)?.rawValue ?? Budget.balanced.rawValue
    draft.preferredPace = answers.pace.proto
    draft.preferredTransport = answers.mobility.proto
    draft.preferAccessible = answers.mobility == .wheelchair
    draft.interestIDs = Set(interestIDs(for: answers.interests, catalogue: catalogue))
    return draft
  }

  /// Offer once: never after it was seen, never to an account with profiles, never when the count is unknown.
  static func shouldOffer(seen: Bool, profileCount: Int?) -> Bool {
    guard !seen, let profileCount else { return false }
    return profileCount == 0
  }

  private static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}
