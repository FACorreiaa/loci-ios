import Foundation
import LociConnectProto

/// The first answer about a place (web: lib/ranking/flow.ts VERDICTS).
nonisolated enum RankingVerdict: String, CaseIterable, Sendable {
  case loved, fine, notForMe

  var label: String {
    switch self {
    case .loved: "Loved"
    case .fine: "Fine"
    case .notForMe: "Not for me"
    }
  }

  var proto: Loci_Ranking_Verdict {
    switch self {
    case .loved: .loved
    case .fine: .fine
    case .notForMe: .notForMe
    }
  }

  /// The notification action that answers with this verdict.
  var actionIdentifier: String { "rate.\(rawValue)" }

  init?(actionIdentifier: String) {
    guard let verdict = Self.allCases.first(where: { $0.actionIdentifier == actionIdentifier }) else { return nil }
    self = verdict
  }
}

/// One answer's result: where the place sits now, and what to compare next.
nonisolated struct RankingStep: Sendable {
  let place: Loci_Ranking_RankedPlace
  let next: Loci_Ranking_Comparison?
}

/// RankingService (loci.ranking), behind a protocol so views test without a session.
nonisolated protocol RankingService: Sendable {
  func rate(_ pending: PendingRating, verdict: RankingVerdict) async throws -> RankingStep
  func compare(poiID: String, otherID: String, better: Bool) async throws -> RankingStep
  func mine(city: String) async throws -> [Loci_Ranking_RankedPlace]
  func user(id: String, city: String) async throws -> [Loci_Ranking_RankedPlace]
}

nonisolated enum RankingAPI {
  private static let client = Loci_Ranking_RankingServiceClient(client: ConnectTransport.shared.protocolClient)

  static func rateRequest(_ pending: PendingRating, verdict: RankingVerdict) -> Loci_Ranking_RatePlaceRequest {
    var request = Loci_Ranking_RatePlaceRequest()
    request.poiID = pending.poiID
    request.poiName = pending.name
    request.cityName = pending.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
    request.category = String(pending.category.prefix(80))
    request.verdict = verdict.proto
    return request
  }

  static func rate(_ pending: PendingRating, verdict: RankingVerdict) async throws -> RankingStep {
    let request = rateRequest(pending, verdict: verdict)
    let response = try await rpc("Could not save that.", request) { await client.ratePlace(request: $0, headers: [:]) }
    return RankingStep(place: response.place, next: response.hasNext ? response.next : nil)
  }

  static func compare(poiID: String, otherID: String, better: Bool) async throws -> RankingStep {
    var request = Loci_Ranking_ComparePlacesRequest()
    request.poiID = poiID
    request.otherPoiID = otherID
    request.better = better
    let response = try await rpc("Could not save that.", request) { await client.comparePlaces(request: $0, headers: [:]) }
    return RankingStep(place: response.place, next: response.hasNext ? response.next : nil)
  }

  static func mine(city: String) async throws -> [Loci_Ranking_RankedPlace] {
    var request = Loci_Ranking_ListMyRankingsRequest()
    request.cityName = city.trimmingCharacters(in: .whitespacesAndNewlines)
    return try await rpc("Could not load your rankings.", request) { await client.listMyRankings(request: $0, headers: [:]) }.places
  }

  /// A friend's rankings. The server refuses anyone who is not a friend.
  static func user(id: String, city: String) async throws -> [Loci_Ranking_RankedPlace] {
    var request = Loci_Ranking_ListUserRankingsRequest()
    request.userID = id
    request.cityName = city.trimmingCharacters(in: .whitespacesAndNewlines)
    return try await rpc("Could not load their rankings.", request) { await client.listUserRankings(request: $0, headers: [:]) }.places
  }
}

nonisolated struct ConnectRankingService: RankingService {
  func rate(_ pending: PendingRating, verdict: RankingVerdict) async throws -> RankingStep {
    try await RankingAPI.rate(pending, verdict: verdict)
  }

  func compare(poiID: String, otherID: String, better: Bool) async throws -> RankingStep {
    try await RankingAPI.compare(poiID: poiID, otherID: otherID, better: better)
  }

  func mine(city: String) async throws -> [Loci_Ranking_RankedPlace] { try await RankingAPI.mine(city: city) }

  func user(id: String, city: String) async throws -> [Loci_Ranking_RankedPlace] {
    try await RankingAPI.user(id: id, city: city)
  }
}

/// The flow's copy, shared with web (lib/ranking/flow.ts).
nonisolated enum HowWasItCopy {
  static func prompt(_ name: String) -> String { "How was \(name)?" }
  static func compare(_ otherName: String) -> String { "Better or worse than \(otherName)?" }
  static func done(_ place: Loci_Ranking_RankedPlace) -> String { "#\(place.rank) in your \(place.cityName) list" }
}

/// One city's top places, grouped from a list already ordered by city then rank
/// (web: groupByCity).
nonisolated enum RankingGroups {
  static let topN = 10

  static func byCity(_ places: [Loci_Ranking_RankedPlace]) -> [(city: String, places: [Loci_Ranking_RankedPlace])] {
    var order: [String] = []
    var groups: [String: [Loci_Ranking_RankedPlace]] = [:]
    for place in places {
      if groups[place.cityName] == nil { order.append(place.cityName) }
      groups[place.cityName, default: []].append(place)
    }
    return order
      .map { (city: $0, places: groups[$0] ?? []) }
      .sorted { $0.places.count > $1.places.count }
      .map { (city: $0.city, places: Array($0.places.prefix(topN))) }
  }
}
