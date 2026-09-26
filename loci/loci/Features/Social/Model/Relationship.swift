import Foundation
import LociConnectProto

/// The caller's relation to another user (loci.social.Relationship), read by
/// raw value so the app does not depend on how the generator spells `NONE`.
/// Not `none`, which reads as `Optional.none`.
nonisolated enum Relationship: Equatable, Sendable {
  case unknown
  case notConnected
  case requested
  case incoming
  case friends
  case blocked
  case isSelf

  init(_ proto: Loci_Social_Relationship) {
    switch proto.rawValue {
    case 1: self = .notConnected
    case 2: self = .requested
    case 3: self = .incoming
    case 4: self = .friends
    case 5: self = .blocked
    case 6: self = .isSelf
    default: self = .unknown
    }
  }
}

nonisolated extension Loci_Social_PublicUser {
  /// The name to show: the display name, else the username.
  var shownName: String { displayName.isEmpty ? username : displayName }

  /// "Ana Sousa" → "AS"; "rui" → "R". For avatar placeholders.
  var initials: String {
    let parts = shownName.split(whereSeparator: \.isWhitespace)
    guard let first = parts.first?.first else { return "?" }
    guard parts.count > 1, let last = parts.last?.first else { return String(first).uppercased() }
    return (String(first) + String(last)).uppercased()
  }
}
