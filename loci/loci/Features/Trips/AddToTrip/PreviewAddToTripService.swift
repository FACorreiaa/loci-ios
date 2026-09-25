import Foundation
import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Add to trip without a server, for `-designPreview addToTrip` and offline
/// runs. Keeps its trips in memory, bumps the version on every add and gives
/// the days new ids, as the server does.
nonisolated final class PreviewAddToTripService: AddToTripService, @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [Loci_Trip_TripDraft]

  init(trips: [Loci_Trip_TripDraft] = PreviewAddToTripService.sampleTrips) {
    stored = trips
  }

  func trips() async throws -> [Loci_Trip_TripDraft] { lock.withLock { stored } }

  func trip(id: String) async throws -> Loci_Trip_TripDraft {
    guard let trip = lock.withLock({ stored.first { $0.id == id } }) else { throw APIError.notFound("No such trip.") }
    return trip
  }

  func addStop(_ request: Loci_Trip_AddStopRequest) async throws -> Loci_Trip_TripDraft {
    try lock.withLock {
      guard let index = stored.firstIndex(where: { $0.id == request.tripID }) else { throw APIError.notFound("No such trip.") }
      guard stored[index].version == request.baseVersion else { throw AddToTripError.staleVersion }
      guard let day = stored[index].days.firstIndex(where: { $0.id == request.dayID }) else { throw AddToTripError.dayMissing }
      stored[index].days[day].stops.append(request.stop)
      Self.save(&stored[index])
      return stored[index]
    }
  }

  func createTrip(_ request: Loci_Trip_SaveTripRequest) async throws -> Loci_Trip_TripDraft {
    var trip = request.trip
    trip.id = UUID().uuidString.lowercased()
    Self.save(&trip)
    lock.withLock { stored.insert(trip, at: 0) }
    return trip
  }

  private static func save(_ trip: inout Loci_Trip_TripDraft) {
    trip.version += 1
    for index in trip.days.indices { trip.days[index].id = UUID().uuidString.lowercased() }
  }

  static var sampleTrips: [Loci_Trip_TripDraft] {
    var lisbon = Loci_Trip_TripDraft()
    lisbon.id = "preview-lisbon"
    lisbon.cityName = "Lisbon"
    lisbon.title = "Lisbon long weekend"
    lisbon.version = 4
    let start = Date(timeIntervalSince1970: 1_790_985_600)  // 2026-10-03 00:00 UTC
    lisbon.days = (1...3).map { number in
      var day = Loci_Trip_TripDay()
      day.id = "preview-lisbon-day-\(number)"
      day.dayNumber = Int32(number)
      day.date = Google_Protobuf_Timestamp(date: start.addingTimeInterval(Double(number - 1) * 86_400))
      day.stops = (0..<(number == 2 ? 1 : 3)).map { index in
        var stop = Loci_Trip_TripStop()
        stop.id = "preview-lisbon-\(number)-\(index)"
        stop.name = "Stop \(index + 1)"
        return stop
      }
      return day
    }
    lisbon.days[2].cityName = "Sintra"
    var porto = Loci_Trip_TripDraft()
    porto.id = "preview-porto"
    porto.cityName = "Porto"
    porto.title = "Porto, undated"
    porto.version = 2
    var day = Loci_Trip_TripDay()
    day.id = "preview-porto-day-1"
    day.dayNumber = 1
    porto.days = [day]
    return [lisbon, porto]
  }
}

/// `-designPreview addToTrip`: a place's detail with the sheet open over it.
struct AddToTripPreview: View {
  var body: some View { NavigationStack { detail }.sheet(isPresented: .constant(true), content: sheet) }

  private var detail: some View { PlaceDetailView(stop: ListEntry.previewStop, destination: .activities, cityName: "Lisbon") }

  private func sheet() -> some View {
    AddToTripSheet(store: AddToTripStore(poi: ListEntry.previewStop, cityName: "Lisbon", service: PreviewAddToTripService()))
  }
}
