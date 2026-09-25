import Foundation
import LociConnectProto
import SwiftProtobuf

/// Offline sample data for the `tripExtras` design previews.
extension Loci_Trip_TripDraft {
  static var previewLisbon: Loci_Trip_TripDraft {
    var trip = Loci_Trip_TripDraft()
    trip.id = "00000000-0000-4000-8000-000000000001"
    trip.title = "Three days in Lisbon"
    trip.cityName = "Lisbon"
    trip.version = 7
    trip.constraints.pace = .moderate
    trip.constraints.budgetLevel = 2
    trip.constraints.mobility = "walking"
    trip.constraints.dayStartMinute = 9 * 60
    trip.constraints.dayEndMinute = 20 * 60
    let names = [["Belém Tower", "Jerónimos Monastery", "Pastéis de Belém"], ["Alfama walk", "São Jorge Castle"], ["LX Factory", "Time Out Market"]]
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let first = utc.date(from: DateComponents(year: 2026, month: 10, day: 4)) ?? Date()
    trip.days = names.enumerated().map { index, stops in
      var day = Loci_Trip_TripDay()
      day.id = "day-\(index + 1)"
      day.dayNumber = Int32(index + 1)
      day.date = Google_Protobuf_Timestamp(date: utc.date(byAdding: .day, value: index, to: first) ?? first)
      day.stops = stops.enumerated().map { order, name in
        var stop = Loci_Trip_TripStop()
        stop.id = "stop-\(index)-\(order)"
        stop.name = name
        stop.orderIndex = Int32(order)
        stop.durationMinutes = 90
        return stop
      }
      return day
    }
    return trip
  }
}

extension TripChecklistStore {
  static func preview(tripID: String) -> TripChecklistStore {
    func item(_ kind: Loci_Trip_ChecklistItemKind, _ text: String, _ position: Int32, done: Bool = false, amount: Int64 = 0) -> Loci_Trip_ChecklistItem {
      var item = Loci_Trip_ChecklistItem()
      item.id = UUID().uuidString.lowercased()
      item.kind = kind
      item.text = text
      item.position = position
      item.done = done
      if kind == .expense {
        item.amountMinor = amount
        item.currency = "EUR"
      }
      return item
    }
    func suggestion(_ text: String, _ reason: String, essential: Bool = false) -> Loci_Trip_PackingSuggestion {
      var suggestion = Loci_Trip_PackingSuggestion()
      suggestion.text = text
      suggestion.reason = reason
      suggestion.essential = essential
      return suggestion
    }
    return TripChecklistStore(
      tripID: tripID,
      service: PreviewTripChecklistService(),
      items: [
        item(.packing, "Passport", 0, done: true),
        item(.packing, "Walking shoes", 1, done: true),
        item(.packing, "Sunscreen", 2),
        item(.expense, "Tram 28 day pass", 0, amount: 1060),
        item(.expense, "Dinner in Alfama", 1, amount: 4250),
      ],
      dismissed: ["umbrella"],
      suggestions: [
        suggestion("Passport", "International trip", essential: true),
        suggestion("Light jacket", "Evenings drop to 16°C"),
        suggestion("Umbrella", "Showers on day 2"),
        suggestion("Power adapter (type F)", "Portugal uses type F sockets", essential: true),
      ],
      availability: .ready
    )
  }
}
