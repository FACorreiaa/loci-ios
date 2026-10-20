import Foundation
import LociConnectProto
import SwiftProtobuf

/// RecapService (loci.recap): a finished trip told as story cards. Web:
/// lib/api/recap.ts. The cards stay as the generated messages; the player
/// switches on `card.card`.
protocol RecapService: Sendable {
  func tripRecap(tripID: String, refresh: Bool) async throws -> Loci_Recap_Recap
  func sharedRecap(code: String) async throws -> Loci_Recap_Recap
  /// Mints (or returns) the public link. Sharing freezes the recap.
  func share(recapID: String) async throws -> URL
  func markViewed(recapID: String) async
  /// One card as a 1080×1920 PNG, drawn by the server.
  func cardImage(recapID: String, cardID: String) async throws -> Data
}

nonisolated struct ConnectRecapService: RecapService {
  private static let client = Loci_Recap_RecapServiceClient(client: ConnectTransport.shared.protocolClient)

  func tripRecap(tripID: String, refresh: Bool) async throws -> Loci_Recap_Recap {
    var request = Loci_Recap_GetTripRecapRequest()
    request.tripID = tripID
    request.refresh = refresh
    return try await rpc("Could not load your recap.", request) { await Self.client.getTripRecap(request: $0, headers: [:]) }.recap
  }

  func sharedRecap(code: String) async throws -> Loci_Recap_Recap {
    var request = Loci_Recap_GetSharedRecapRequest()
    request.shareCode = code
    return try await rpc("This recap isn't shared any more.", request) { await Self.client.getSharedRecap(request: $0, headers: [:]) }.recap
  }

  func share(recapID: String) async throws -> URL {
    var request = Loci_Recap_ShareRecapRequest()
    request.recapID = recapID
    let response = try await rpc("Could not make a link.", request) { await Self.client.shareRecap(request: $0, headers: [:]) }
    guard let url = URL(string: response.shareURL) else { throw APIError.server("Could not make a link.") }
    return url
  }

  func markViewed(recapID: String) async {
    var request = Loci_Recap_MarkRecapViewedRequest()
    request.recapID = recapID
    _ = await Self.client.markRecapViewed(request: request, headers: [:])
  }

  func cardImage(recapID: String, cardID: String) async throws -> Data {
    var request = Loci_Recap_RenderRecapCardImageRequest()
    request.recapID = recapID
    request.cardID = cardID
    request.format = .story
    return try await rpc("Could not make the image.", request) { await Self.client.renderRecapCardImage(request: $0, headers: [:]) }.png
  }
}

nonisolated enum RecapRules {
  /// Cards this build draws. A newer server may send more; they are skipped.
  /// An allowlist rather than `card != nil`: once the proto gains a card type,
  /// it decodes as non-nil before any view for it exists.
  static func playable(_ cards: [Loci_Recap_RecapCard]) -> [Loci_Recap_RecapCard] { cards.filter { isDrawn($0) } }

  static func isDrawn(_ card: Loci_Recap_RecapCard) -> Bool {
    switch card.card {
    case .intro, .places, .route, .days, .taste, .highlights, .progress, .field, .friends, .outro: true
    default: false
    }
  }

  /// Whether a trip is over, so its recap can be asked for. Mirrors the
  /// server: the end date has passed (or the last dated day, when there is no
  /// end date), or every day has been walked.
  static func tripHasEnded(_ trip: Loci_Trip_TripDraft, now: Date = .now, calendar: Calendar = .current) -> Bool {
    if !trip.days.isEmpty, trip.days.allSatisfy(\.hasCompletedAt) { return true }
    let today = calendar.startOfDay(for: now)
    if trip.hasEndDate, let end = Self.localDate(trip.endDate, calendar: calendar) { return end < today }
    let last = trip.days.filter(\.hasDate).map { calendar.startOfDay(for: $0.date.date) }.max()
    guard let last else { return false }
    return last < today
  }

  /// "2026-10-15" as midnight in `calendar`'s zone.
  static func localDate(_ iso: String, calendar: Calendar) -> Date? {
    let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }

  /// "41 km", "1,204 km", "0.8 km".
  static func km(_ value: Double) -> String {
    guard value.isFinite, value > 0 else { return "0 km" }
    if value < 10 {
      let text = value.formatted(.number.precision(.fractionLength(0...1)))
      return "\(text) km"
    }
    return "\(Int(value.rounded()).formatted()) km"
  }

  static func basisCaption(_ basis: Loci_Recap_RouteBasis) -> String {
    switch basis {
    case .legs: "along your legs"
    case .cities: "as the crow flies between cities"
    case .visits: "between the places you visited"
    default: ""
    }
  }

  static func evidence(_ count: Int32, _ kind: Loci_Recap_TasteEvidenceKind) -> String {
    guard count > 0 else { return "" }
    let noun =
      switch kind {
      case .saves: "save"
      case .visits: "visit"
      case .reviews: "review"
      default: "signal"
      }
    return "From \(count) \(noun)\(count == 1 ? "" : "s")"
  }

  static func trend(_ trend: Loci_Recap_TasteTrend) -> String {
    switch trend {
    case .new: "New"
    case .growing: "Growing"
    case .strong: "Strong"
    default: ""
    }
  }

  static func initials(_ name: String) -> String {
    let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init).joined()
    return letters.isEmpty ? "?" : letters.uppercased()
  }
}
