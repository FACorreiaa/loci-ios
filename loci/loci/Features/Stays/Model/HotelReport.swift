import Foundation
import LociConnectProto

/// How a hotel comparison report is read into the card (web:
/// components/chat/HotelComparisonCard.tsx). Pure, so every line the card
/// draws can be tested. Every string in a report is plain text: some of it
/// was written from web pages, so nothing here builds markdown or links from it.
nonisolated enum HotelReport {
  typealias Report = Loci_Chat_HotelComparisonReport
  typealias Hotel = Loci_Chat_ComparedHotel

  /// One line of the side-by-side table: a value per hotel, in report order.
  struct Row: Equatable, Sendable, Identifiable {
    let id: Int
    let label: String
    let values: [String]
  }

  /// A page the report drew on. `url` is nil unless it is https.
  struct Source: Equatable, Sendable, Identifiable {
    let id: Int
    let text: String
    let url: URL?
  }

  static let missing = "—"
  static let unidentifiedNote = String(localized: "Not matched to a known hotel. Compared on what you wrote about it.")

  /// The hotel's name, or its place in the list when the listing gave none.
  static func name(_ hotel: Hotel, at index: Int) -> String {
    let name = hotel.stay.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? String(localized: "Hotel \(index + 1)") : name
  }

  static func names(_ report: Report) -> [String] {
    report.hotels.enumerated().map { name($0.element, at: $0.offset) }
  }

  /// "Verdi 254 vs Hotel X · Barcelona".
  static func title(_ report: Report) -> String {
    let versus = names(report).joined(separator: String(localized: " vs "))
    let city = report.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
    return city.isEmpty ? versus : "\(versus) · \(city)"
  }

  /// The hotel the verdict favours, when it names one that is in the report.
  static func recommendedIndex(_ report: Report) -> Int? {
    guard report.hasRecommendedIndex else { return nil }
    let index = Int(report.recommendedIndex)
    return report.hotels.indices.contains(index) ? index : nil
  }

  /// "12 Nov to 15 Nov", from the report's own dates, as the server wrote them.
  static func dates(_ report: Report) -> String? {
    guard report.hasCheckIn, report.hasCheckOut, !report.checkIn.isEmpty, !report.checkOut.isEmpty else { return nil }
    return String(localized: "\(report.checkIn) to \(report.checkOut)")
  }

  /// The table, exactly as the server laid it out: its rows are complete and
  /// in display order (what the traveller said, stars, price now, nearest
  /// stops, facilities…), so nothing is added from the hotels' own fields,
  /// which repeat them. A row short of a value gets a dash; a row nobody has
  /// anything for is left out.
  static func rows(_ report: Report) -> [Row] {
    let count = report.hotels.count
    return report.rows
      .map { row in
        (
          row.label.trimmingCharacters(in: .whitespacesAndNewlines),
          (0..<count).map { row.values.indices.contains($0) ? row.values[$0].trimmingCharacters(in: .whitespacesAndNewlines) : "" }
        )
      }
      .filter { _, values in values.contains { !$0.isEmpty } }
      .enumerated()
      .map { offset, row in Row(id: offset, label: row.0, values: row.1.map { $0.isEmpty ? missing : $0 }) }
  }

  /// Where a live rate can be booked: the one thing drawn from `live_price`
  /// (its amounts are already in the table). Only when it is https.
  static func bookingURL(_ hotel: Hotel) -> URL? {
    hotel.hasLivePrice ? TransitFormat.httpsURL(hotel.livePrice.bookingURL) : nil
  }

  /// "Title — Publisher"; the link only when it is https.
  static func sources(_ report: Report) -> [Source] {
    report.sources.enumerated().compactMap { offset, source in
      let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let publisher = source.publisher.trimmingCharacters(in: .whitespacesAndNewlines)
      let text = [title, publisher].filter { !$0.isEmpty }.joined(separator: " — ")
      let url = TransitFormat.httpsURL(source.url)
      guard !text.isEmpty || url != nil else { return nil }
      return Source(id: offset, text: text.isEmpty ? (url?.host() ?? "") : text, url: url)
    }
  }

  /// A hotel can go on a trip when the report knows its name and city: both
  /// are required by SetStay. An unidentified listing may have neither.
  static func canAdd(_ hotel: Hotel) -> Bool {
    hotel.hasStay && !hotel.stay.name.trimmingCharacters(in: .whitespaces).isEmpty
      && !hotel.stay.cityName.trimmingCharacters(in: .whitespaces).isEmpty
  }

  /// The proposal `stay_proposal_id` names, when it is among those received.
  static func stayProposal(for report: Report, in proposals: [Loci_Chat_ActionProposal]) -> Loci_Chat_ActionProposal? {
    guard !report.stayProposalID.isEmpty else { return nil }
    return proposals.first { $0.id == report.stayProposalID }
  }

  /// What the card says once a hotel is the trip's stay.
  static func addedMessage(hotel: String, trip: String) -> String {
    trip.isEmpty ? String(localized: "\(hotel) is now your stay.") : String(localized: "\(hotel) is now your stay on \(trip).")
  }
}
