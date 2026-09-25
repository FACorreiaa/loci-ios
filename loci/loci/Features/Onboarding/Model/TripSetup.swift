import Foundation
import LociConnectProto

/// The first-run profile wizard's rules (web: lib/trip-setup.ts): four
/// questions fill in the default travel profile, sent as the server expects
/// it — catalogue ids for interests, real pace and transport enums — and
/// offered once, to a brand-new account.
///
/// Every account has a profile from its first second: the server's
/// `AFTER INSERT ON users` trigger creates "Default". So the offer cannot wait
/// for zero profiles (it never fired), and the save updates that profile in
/// place rather than adding a second one.
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
    /// Step-free travel is transit plus `preferAccessiblePois`: the enum has no
    /// wheelchair case, and WALK would bias the plan towards long on-foot legs.
    var proto: Loci_Profile_TransportPreference {
      switch self {
      case .walking: .walk
      case .transit, .wheelchair: .public
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

  /// The name the wizard gives the profile, unless the user already chose one.
  static let profileName = "My Trip Profile"
  /// The name of the profile the server creates for every new user (migration 0008).
  static let serverDefaultName = "Default"

  /// The slice of a stored profile the first-run rules read.
  struct ExistingProfile: Equatable, Sendable {
    var id: String
    var name: String
    var isDefault: Bool
    var vibes: [String] = []
    var dietaryNeeds: [String] = []
    var interestIDs: [String] = []
    var tagIDs: [String] = []
  }

  /// Still exactly what the server created at sign-up: nothing a person chose.
  static func isUntouched(_ profile: ExistingProfile) -> Bool {
    profile.name == serverDefaultName && profile.interestIDs.isEmpty && profile.tagIDs.isEmpty
      && profile.vibes.isEmpty && profile.dietaryNeeds.isEmpty
  }

  /// Offer once, to a brand-new account: never after it was seen, and never to
  /// an account that already has a profile someone customised.
  static func shouldOffer(isNewUser: Bool, seen: Bool, profiles: [ExistingProfile]) -> Bool {
    guard isNewUser, !seen else { return false }
    return profiles.allSatisfy(isUntouched)
  }

  /// UserDefaults key: the wizard was shown (finished or skipped) to this user on this phone.
  static func seenKey(userID: String) -> String { "loci_trip_setup_seen:\(userID)" }

  enum Save: Equatable, Sendable {
    case create
    /// Update the default profile in place, under `name`.
    case update(profileID: String, name: String)
  }

  /// Update the default profile, keeping a name the user chose; create only
  /// when there is no default to update.
  static func save(existing: [ExistingProfile]) -> Save {
    guard let target = existing.first(where: \.isDefault) else { return .create }
    let name = target.name.isEmpty || target.name == serverDefaultName ? profileName : target.name
    return .update(profileID: target.id, name: name)
  }

  /// The answers applied onto `base` (the stored default profile's draft, so
  /// vibes, dietary needs, tags and every section the wizard doesn't ask about
  /// go back unchanged — update replaces lists wholesale), or onto a fresh
  /// draft when creating. Main-actor, like the editor's draft type.
  @MainActor static func draft(
    _ answers: Answers,
    catalogue: [Interest],
    base: TravelProfileDraft = TravelProfileDraft(isDefault: true),
    name: String = profileName
  ) -> TravelProfileDraft {
    var draft = base
    draft.name = name
    draft.isDefault = true
    draft.budgetLevel = Budget(rawValue: answers.budget)?.rawValue ?? Budget.balanced.rawValue
    draft.preferredPace = answers.pace.proto
    draft.preferredTransport = answers.mobility.proto
    draft.preferAccessible = answers.mobility == .wheelchair
    draft.interestIDs = Set(interestIDs(for: answers.interests, catalogue: catalogue))
    return draft
  }

  private static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}

extension TripSetup.ExistingProfile {
  nonisolated init(_ profile: Loci_Profile_UserPreferenceProfile) {
    self.init(
      id: profile.id,
      name: profile.profileName,
      isDefault: profile.isDefault,
      vibes: profile.preferredVibes,
      dietaryNeeds: profile.dietaryNeeds,
      interestIDs: profile.interests.map(\.id),
      tagIDs: profile.tags.map(\.id)
    )
  }
}
