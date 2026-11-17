import Foundation
import LociConnectProto
import Observation

/// How to get around from each of a trip's stays, loaded beside the trip
/// (GetStayTransport, one call per city with a stay). Read-only, so every
/// role sees it.
@MainActor @Observable final class StayTransportModel {
  enum Phase: Equatable {
    case loading
    case loaded(Loci_Trip_StayTransport)
    case failed
  }

  typealias Fetch = @Sendable (_ tripID: String, _ cityName: String) async throws(TripRPCError) -> Loci_Trip_StayTransport

  /// By the stay's city name, as the trip spells it.
  private(set) var phases: [String: Phase] = [:]
  @ObservationIgnored private let fetch: Fetch

  init(fetch: @escaping Fetch = { tripID, city throws(TripRPCError) in try await TripPlanAPI.stayTransport(tripID: tripID, cityName: city) }) {
    self.fetch = fetch
  }

  /// Changes when the answer could: another stay, a stay somewhere else, or a
  /// day that now begins at a different stop. A view reloads on it.
  nonisolated static func key(_ trip: Loci_Trip_TripDraft) -> String {
    let stays = trip.stays.map { "\($0.cityName)|\($0.poiID)|\($0.name)|\($0.latitude),\($0.longitude)" }
    let firsts = trip.days.map { day in
      let first = day.stops.min { $0.orderIndex < $1.orderIndex }
      return "\(day.dayNumber):\(first?.poiID ?? "")|\(first?.name ?? "")"
    }
    return ([trip.id] + stays + ["#"] + firsts).joined(separator: ";")
  }

  func phase(for city: String) -> Phase? { phases[city] }

  private var loaded: [Loci_Trip_StayTransport] {
    phases.values.compactMap { if case .loaded(let transport) = $0 { transport } else { nil } }
  }

  /// "From your hotel" for a day, once the stay it belongs to has loaded.
  func dayStart(for day: Loci_Trip_TripDay) -> Loci_Trip_DayStart? {
    StayTransportFormat.dayStart(in: loaded, dayID: day.id, dayNumber: day.dayNumber)
  }

  /// Read every stay's transport. What is on show stays until its
  /// replacement arrives, so a reload does not blank the section.
  func load(_ trip: Loci_Trip_TripDraft) async {
    let cities = trip.stays.map(\.cityName).filter { !$0.isEmpty }
    phases = phases.filter { cities.contains($0.key) }
    for city in cities {
      if phases[city] == nil || phases[city] == .failed { phases[city] = .loading }
      do {
        phases[city] = .loaded(try await fetch(trip.id, city))
      } catch {
        // The view went away mid-call: leave what was there.
        if error.isCancelled || Task.isCancelled {
          if phases[city] == .loading { phases[city] = nil }
          return
        }
        // A server without the RPC yet has no section to show; any other
        // failure says so and can be tried again.
        phases[city] = error.isUnimplemented ? nil : .failed
      }
    }
  }
}
