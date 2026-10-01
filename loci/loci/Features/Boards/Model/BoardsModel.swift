import Foundation
import LociConnectProto
import SwiftProtobuf

/// Pure rules the boards screens share with web (lib/api/boards.ts), kept out
/// of the views so they are unit-tested.
nonisolated enum BoardsModel {
  /// What the score and the caller's vote become when an arrow is pressed:
  /// pressing the arrow already lit clears the vote.
  static func applyVote(score: Int32, myVote: Int32, pressed: Int32) -> (score: Int32, myVote: Int32) {
    let next: Int32 = myVote == pressed ? 0 : pressed
    return (score - myVote + next, next)
  }

  /// A board address from a name: "Trip reports!" → "trip-reports".
  static func slugify(_ name: String) -> String {
    let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
    var out = ""
    var lastDash = true
    for scalar in folded.unicodeScalars {
      if CharacterSet.lowercaseLetters.contains(scalar) && scalar.isASCII || CharacterSet.decimalDigits.contains(scalar) && scalar.isASCII {
        out.unicodeScalars.append(scalar)
        lastDash = false
      } else if !lastDash {
        out.append("-")
        lastDash = true
      }
    }
    while out.hasSuffix("-") { out.removeLast() }
    if out.count > 32 {
      out = String(out.prefix(32))
      while out.hasSuffix("-") { out.removeLast() }
    }
    return out
  }

  static func isValidSlug(_ slug: String) -> Bool {
    (3...32).contains(slug.count) && slug.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" }
  }

  /// An http(s) link with a host, or nil.
  static func isLink(_ text: String) -> Bool {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)), let scheme = url.scheme?.lowercased() else { return false }
    return (scheme == "http" || scheme == "https") && !(url.host() ?? "").isEmpty
  }

  struct CommentNode: Identifiable {
    let comment: Loci_Boards_V1_Comment
    var children: [CommentNode]
    var id: String { comment.id }
  }

  /// Nests the flat comment list the server returns. Replies whose parent is
  /// missing surface at the top level rather than vanish.
  static func commentTree(_ comments: [Loci_Boards_V1_Comment]) -> [CommentNode] {
    let ids = Set(comments.map(\.id))
    var children: [String: [Loci_Boards_V1_Comment]] = [:]
    var roots: [Loci_Boards_V1_Comment] = []
    for c in comments { if !c.parentID.isEmpty, ids.contains(c.parentID) { children[c.parentID, default: []].append(c) } else { roots.append(c) } }
    func build(_ c: Loci_Boards_V1_Comment) -> CommentNode { CommentNode(comment: c, children: (children[c.id] ?? []).map(build)) }
    return roots.map(build)
  }

  /// Flattens a tree into rows with their depth, for a List.
  static func flatten(_ nodes: [CommentNode], depth: Int = 0) -> [(comment: Loci_Boards_V1_Comment, depth: Int)] {
    nodes.flatMap { [($0.comment, depth)] + flatten($0.children, depth: depth + 1) }
  }

  /// "2h", "3d": coarse, like the web feed.
  static func age(_ timestamp: Google_Protobuf_Timestamp, now: Date = Date()) -> String {
    let seconds = now.timeIntervalSince(timestamp.date)
    let minutes = Int(seconds / 60)
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h" }
    return "\(hours / 24)d"
  }
}

extension Loci_Boards_V1_Sanction {
  /// "You're muted from boards until 3 Oct, 14:00."
  var viewerExplanation: String {
    let verb = kind == .ban ? "banned" : "muted"
    let until = hasExpiresAt ? " until \(expiresAt.date.formatted(date: .abbreviated, time: .shortened))" : ""
    return "You're \(verb) from boards\(until). You can still read, but you can't post, comment or vote."
  }
}
