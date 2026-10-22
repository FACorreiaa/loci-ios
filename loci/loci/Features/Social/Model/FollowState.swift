import Foundation
import LociConnectProto

/// Whether the caller follows someone (loci.social.FollowState), read by raw
/// value like `Relationship`. Not `none`, which reads as `Optional.none`.
nonisolated enum FollowState: Equatable, Sendable {
  case unknown
  case notFollowing
  case requested
  case following
  case blocked
  /// The caller's own profile. The server has no follow state for it; the
  /// legacy relationship says SELF.
  case isSelf

  init(_ proto: Loci_Social_FollowState) {
    switch proto.rawValue {
    case 1: self = .notFollowing
    case 2: self = .requested
    case 3: self = .following
    case 4: self = .blocked
    default: self = .unknown
    }
  }
}

/// One side of a follow, as the follow button shows it: whether I follow them
/// and whether they follow me. Both ways is a friendship.
nonisolated struct FollowEdge: Equatable, Sendable {
  var state: FollowState
  var followsYou: Bool

  static let unknown = FollowEdge(state: .unknown, followsYou: false)

  /// `relationship` only tells the caller's own profile apart: FollowState has no SELF.
  init(state: Loci_Social_FollowState, followsYou: Bool, relationship: Loci_Social_Relationship = .unspecified) {
    self.init(state: Relationship(relationship) == .isSelf ? .isSelf : FollowState(state), followsYou: followsYou)
  }

  init(state: FollowState, followsYou: Bool) {
    self.state = state
    self.followsYou = followsYou
  }

  var isFriend: Bool { state == .following && followsYou }

  /// The button's label: Follow, Follow back, Requested, Following or Friends.
  var title: String {
    switch state {
    case .notFollowing, .unknown: followsYou ? "Follow back" : "Follow"
    case .requested: "Requested"
    case .following: followsYou ? "Friends" : "Following"
    case .blocked: "Unblock"
    case .isSelf: ""
    }
  }
}

nonisolated extension Loci_Social_FeedItem {
  /// "reached Cartographer · Gold", "explored Lisbon for the first time": what
  /// the actor did, after their name.
  var headline: String {
    switch detail {
    case .achievement(let a): "unlocked \(a.label)"
    case .city(let c): c.country.isEmpty ? "explored \(c.cityName) for the first time" : "explored \(c.cityName), \(c.country) for the first time"
    case .trip(let t):
      switch kind {
      case .tripShared: "shared a trip: \(t.title.isEmpty ? t.cityName : t.title)"
      default: "finished a trip: \(t.title.isEmpty ? t.cityName : t.title)"
      }
    case nil: "was out exploring"
    }
  }

  /// achievement, city or trip: what analytics calls it, as web does.
  var detailKind: String {
    switch detail {
    case .achievement: "achievement"
    case .city: "city"
    case .trip: "trip"
    case nil: "unknown"
    }
  }

  /// "Cheered by Ana and 2 others"; nil before anyone has.
  var cheerLine: String? {
    guard cheerCount > 0 else { return nil }
    let count = Int(cheerCount)
    if cheeredByMe {
      return count == 1 ? "You cheered" : "You and \(Self.others(count - 1)) cheered"
    }
    guard let first = recentCheerers.first?.shownName else { return count == 1 ? "1 cheer" : "\(count) cheers" }
    return count == 1 ? "\(first) cheered" : "\(first) and \(Self.others(count - 1)) cheered"
  }

  private static func others(_ n: Int) -> String { n == 1 ? "1 other" : "\(n) others" }

  /// The item with the caller's cheer set or taken back, before the server answers.
  func cheered(_ on: Bool) -> Self {
    guard on != cheeredByMe else { return self }
    var item = self
    item.cheeredByMe = on
    item.cheerCount = max(0, cheerCount + (on ? 1 : -1))
    return item
  }
}
