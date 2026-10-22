import Foundation
import LociConnectProto

/// A track's rung (loci.achievement.AchievementTier), by raw value. Moments
/// and secrets have none.
nonisolated enum AchievementTier: Int, Comparable, Sendable, CaseIterable {
  case unranked = 0, bronze, silver, gold, platinum

  init(_ proto: Loci_Achievement_AchievementTier) { self = Self(rawValue: proto.rawValue) ?? .unranked }

  var name: String {
    switch self {
    case .unranked: ""
    case .bronze: "Bronze"
    case .silver: "Silver"
    case .gold: "Gold"
    case .platinum: "Platinum"
    }
  }

  static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Tracks climb tiers; a moment happens once; a secret is hidden until earned.
nonisolated enum AchievementKind: Int, Sendable, CaseIterable {
  case unknown = 0, track, moment, secret

  init(_ proto: Loci_Achievement_AchievementKind) { self = Self(rawValue: proto.rawValue) ?? .unknown }

  var title: String {
    switch self {
    case .track, .unknown: "Tracks"
    case .moment: "Moments"
    case .secret: "Secrets"
    }
  }
}

/// How an achievement reads, shared by the full record and the summary the
/// feed and showcase carry (web: lib/api/achievements.ts).
nonisolated enum AchievementText {
  /// "Cartographer · Gold" for a track rung; the title alone otherwise.
  static func label(title: String, kind: AchievementKind, tier: AchievementTier) -> String {
    kind == .track && tier != .unranked ? "\(title) · \(tier.name)" : title
  }

  /// "Held by 4% of explorers"; nil while the server hides rarity (too few people yet).
  static func rarity(_ pct: Float?) -> String? {
    guard let pct else { return nil }
    return pct < 1 ? "Held by under 1% of explorers" : "Held by \(Int(pct.rounded()))% of explorers"
  }

  /// Orders unlocks as the server's push does: a secret, then the highest tier, then a moment.
  static func rank(kind: AchievementKind, tier: AchievementTier) -> Int {
    switch kind {
    case .secret: 10
    case .track: 1 + tier.rawValue
    default: 1
    }
  }

  /// The SF Symbol for the server's semantic icon key (a lucide name, which
  /// web draws). An unknown key falls back to a rosette, so new art never
  /// needs an app release.
  static func symbol(_ icon: String) -> String { symbols[icon] ?? fallbackSymbol }

  static let fallbackSymbol = "rosette"

  static let symbols: [String: String] = [
    "aperture": "camera.aperture",
    "binoculars": "binoculars.fill",
    "bookmark": "bookmark.fill",
    "camera": "camera.fill",
    "copy": "doc.on.doc.fill",
    "crown": "crown.fill",
    "feather": "pencil.and.outline",
    "flag": "flag.fill",
    "flame": "flame.fill",
    "footprints": "shoeprints.fill",
    "globe": "globe.europe.africa.fill",
    "handshake": "person.2.fill",
    "house": "house.fill",
    "library": "books.vertical.fill",
    "list-checks": "checklist",
    "list-ordered": "list.number",
    "locate": "location.fill",
    "lock": "lock.fill",
    "map": "map.fill",
    "map-pin": "mappin",
    "map-pin-plus": "mappin.and.ellipse",
    "megaphone": "megaphone.fill",
    "milestone": "signpost.right.fill",
    "moon": "moon.stars.fill",
    "notebook-pen": "square.and.pencil",
    "package": "shippingbox.fill",
    "pen-line": "pencil.line",
    "repeat": "repeat",
    "route": "point.topleft.down.to.point.bottomright.curvepath.fill",
    "signpost": "signpost.right.and.left.fill",
    "sun": "sun.max.fill",
    "sunrise": "sunrise.fill",
    "thumbs-up": "hand.thumbsup.fill",
    "user-plus": "person.badge.plus",
    "users": "person.3.fill",
  ]
}

nonisolated extension Loci_Achievement_Achievement {
  var tierValue: AchievementTier { AchievementTier(tier) }
  var kindValue: AchievementKind { AchievementKind(kind) }
  var label: String { AchievementText.label(title: title, kind: kindValue, tier: tierValue) }
  var isEarned: Bool { hasEarnedAt }
  var symbol: String { AchievementText.symbol(icon) }
  var rarityLine: String? { AchievementText.rarity(hasRarityPct ? rarityPct : nil) }
  var rank: Int { AchievementText.rank(kind: kindValue, tier: tierValue) }

  /// 0…1 toward the next rung (or the moment); 1 when nothing is left.
  var progressShare: Double {
    guard nextTarget > 0 else { return 1 }
    return min(1, max(0, Double(progress) / Double(nextTarget)))
  }

  /// How close the next rung is, for "Up next" ordering.
  var closeness: Double { nextTarget > 0 ? Double(progress) / Double(nextTarget) : 0 }

  var summary: Loci_Achievement_AchievementSummary {
    var s = Loci_Achievement_AchievementSummary()
    s.id = id
    s.title = title
    s.icon = icon
    s.kind = kind
    s.tier = tier
    if hasEarnedAt { s.earnedAt = earnedAt }
    return s
  }
}

nonisolated extension Loci_Achievement_AchievementSummary {
  var tierValue: AchievementTier { AchievementTier(tier) }
  var kindValue: AchievementKind { AchievementKind(kind) }
  var label: String { AchievementText.label(title: title, kind: kindValue, tier: tierValue) }
  var symbol: String { AchievementText.symbol(icon) }
}

nonisolated extension Array where Element == Loci_Achievement_Achievement {
  /// The unlock worth announcing: the rarest kind, then the highest tier.
  var best: Loci_Achievement_Achievement? { self.max { $0.rank < $1.rank } }
}
