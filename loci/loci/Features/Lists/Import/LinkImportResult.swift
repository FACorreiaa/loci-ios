import Foundation
import LociConnectProto

/// One place a shared link mentions. Without a Loci id it is shown, not saved.
nonisolated struct ImportedPlace: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  let city: String
  let note: String
  let poiID: String?
  let address: String?
  let category: String?

  var canSave: Bool { poiID != nil }
}

/// What a link held (web: lib/import/link-import.ts toImportView).
nonisolated struct LinkImportResult: Equatable, Sendable {
  let source: String
  let title: String
  let city: String
  let places: [ImportedPlace]

  init(_ response: Loci_Place_ImportPlacesResponse) {
    source = Self.sourceName(response.source)
    title = response.sourceTitle
    city = response.cityName
    places = response.places.enumerated().map { index, place in
      ImportedPlace(
        // Names can repeat across cities; the position keeps ids unique.
        id: "\(index):\(place.hasPoiID ? place.poiID : place.name)",
        name: place.name,
        city: place.cityName,
        note: place.note,
        poiID: place.hasPoiID && !place.poiID.isEmpty ? place.poiID : nil,
        address: place.hasAddress && !place.address.isEmpty ? place.address : nil,
        category: place.hasCategory && !place.category.isEmpty ? place.category : nil,
      )
    }
  }

  /// Every place that can be saved starts picked.
  var defaultSelection: Set<String> { Set(places.filter(\.canSave).map(\.id)) }

  /// A new list is named after the video or post, else its city.
  var defaultListName: String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return String(trimmed.prefix(60)).trimmingCharacters(in: .whitespaces) }
    if !city.isEmpty { return "Places in \(city)" }
    return "Imported places"
  }

  private static func sourceName(_ source: Loci_Place_ImportSource) -> String {
    switch source {
    case .googleMaps: "Google Maps"
    case .tiktok: "TikTok"
    case .instagram: "Instagram"
    case .youtube: "YouTube"
    case .web: "Web page"
    default: "Link"
    }
  }
}

nonisolated enum LinkImportTarget: Hashable, Sendable {
  case new
  case existing(String)
}

nonisolated struct LinkImportOutcome: Equatable, Sendable {
  let listID: String
  var added = 0
  /// Already in the list: AddListItem answers AlreadyExists.
  var already = 0
  var failed = 0
}

/// Tidies what a person pastes: share sheets add a line of text before the
/// link, and a link copied from an address bar may have no scheme.
nonisolated enum LinkImportLink {
  static func normalized(_ raw: String) -> String? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidates = text.split(whereSeparator: \.isWhitespace).map(String.init)
    let found = candidates.first { $0.contains("://") } ?? (candidates.count == 1 ? candidates[0] : nil)
    guard var link = found else { return nil }
    if !link.contains("://") {
      guard link.contains(".") else { return nil }
      link = "https://" + link
    }
    guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
      let host = url.host(), host.contains(".")
    else { return nil }
    return link
  }
}

/// ImportPlaces plus the two list calls that keep its places.
nonisolated protocol LinkImportService: Sendable {
  func importPlaces(url: String, cityHint: String) async throws -> LinkImportResult
  /// The new list's id.
  func createList(name: String) async throws -> String
  func addPlace(poiID: String, toList listID: String) async throws
}

nonisolated struct ConnectLinkImportService: LinkImportService {
  func importPlaces(url: String, cityHint: String) async throws -> LinkImportResult {
    var request = Loci_Place_ImportPlacesRequest()
    request.url = url
    if !cityHint.isEmpty { request.cityHint = cityHint }
    let sent = request
    let response = try await rpc("Couldn't import that link.", sent) { await ResultsAPI.places.importPlaces(request: $0, headers: [:]) }
    return LinkImportResult(response)
  }

  func createList(name: String) async throws -> String {
    let userID = await AuthSessionManager.shared.currentUserID ?? "me"
    let list = try await ListsAPI.create(userId: userID, form: ListForm(name: name, description: "Imported from a link"), cityId: nil)
    return list.id
  }

  func addPlace(poiID: String, toList listID: String) async throws {
    let userID = await AuthSessionManager.shared.currentUserID ?? "me"
    try await ListsAPI.addPlace(userId: userID, listId: listID, poiID: poiID)
  }
}
