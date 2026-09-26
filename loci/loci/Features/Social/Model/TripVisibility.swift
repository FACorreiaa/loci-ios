import Foundation
import LociConnectProto

/// Who besides the owner may open a trip (loci.trip.TripVisibility), with the
/// words web's share panel uses (lib/social/visibility.ts).
nonisolated enum TripVisibility: Int, CaseIterable, Identifiable, Sendable {
  case onlyMe = 1
  case friends = 2
  case link = 3
  case everyone = 4

  var id: Int { rawValue }

  init(_ proto: Loci_Trip_TripVisibility) { self = Self(rawValue: proto.rawValue) ?? .onlyMe }

  var proto: Loci_Trip_TripVisibility { Loci_Trip_TripVisibility(rawValue: rawValue) ?? .unspecified }

  var label: String {
    switch self {
    case .onlyMe: "Only me"
    case .friends: "Friends"
    case .link: "Anyone with the link"
    case .everyone: "Public"
    }
  }

  var detail: String {
    switch self {
    case .onlyMe: "Nobody else can open it."
    case .friends: "Your friends see it on their feed and your profile."
    case .link: "Not listed anywhere; whoever has the link can open it."
    case .everyone: "Anyone with the link, and listed on your profile."
    }
  }

  var systemImage: String {
    switch self {
    case .onlyMe: "lock"
    case .friends: "person.2"
    case .link: "link"
    case .everyone: "globe"
    }
  }

  /// Whether a trip at this level has a link worth sharing.
  var hasLink: Bool { self != .onlyMe }
}

/// Web addresses the app shares; the same paths open back in the app
/// (AASA on the web side, `AppLink` here).
nonisolated enum SocialLinks {
  static let origin = "https://lociai.fyi"

  static func sharedTrip(code: String) -> URL? { URL(string: "\(origin)/t/\(code)") }
  static func profile(username: String) -> URL? { URL(string: "\(origin)/u/\(username)") }
}
