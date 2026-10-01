import Foundation
import LociConnectProto

/// What a share sheet is about (web: ShareModal's contentType/contentId). The
/// server mints one link per target; the text is what we shared before links.
nonisolated enum ShareTarget: Equatable, Sendable {
  case place(id: String, name: String, destination: SearchDestination, address: String)
  case itinerary(id: String, title: String)
  case list(id: String, name: String)

  var contentType: Loci_Share_ShareContentType {
    switch self {
    case .place(_, _, let destination, _):
      switch destination {
      case .hotels: .hotel
      case .restaurants: .restaurant
      case .activities: .activity
      case .itinerary: .poi
      }
    case .itinerary: .itinerary
    case .list: .list
    }
  }

  var contentID: String {
    switch self {
    case .place(let id, _, _, _), .itinerary(let id, _), .list(let id, _): id
    }
  }

  var title: String {
    switch self {
    case .place(_, let name, _, _), .list(_, let name): name
    case .itinerary(_, let title): title
    }
  }

  /// web's content_type property on share_link_created.
  var analyticsName: String {
    switch self {
    case .place: "place"
    case .itinerary: "itinerary"
    case .list: "list"
    }
  }

  /// Today's text share: name, address, signature, home page.
  var fallbackText: String {
    var lines = [title]
    if case .place(_, _, _, let address) = self { lines.append(address) }
    lines += [ShareText.signature, ShareText.homeURL]
    return lines.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  /// Links hang off a stored id; a name-keyed place has nothing to point at.
  var canLink: Bool {
    switch self {
    case .place(let id, _, _, _): SavedPlace.isStoredID(id)
    case .itinerary(let id, _), .list(let id, _): !id.isEmpty
    }
  }
}

/// Where a share link lives (web: SHARE_HOME_URL + /share/<code>). The API
/// mints links on its own host today; the app opens either.
nonisolated enum ShareLinks {
  static let origin = SocialLinks.origin
  static let apiHost = "api.lociai.fyi"

  static func share(code: String) -> URL? {
    guard !code.isEmpty else { return nil }
    return URL(string: "\(origin)/share/\(code)")
  }
}
