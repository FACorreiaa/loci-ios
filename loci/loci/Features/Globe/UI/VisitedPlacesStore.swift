import Foundation
import LociConnectProto
import SwiftProtobuf

/// Places I've been: every place visit on record, paged from the server and
/// grouped by city for the screen (web: routes/visited, lib/visited/group.ts).
@MainActor @Observable final class VisitedPlacesStore {
  struct CityVisits: Identifiable {
    let city: String
    let places: [Loci_Travelhistory_VisitedPOI]
    var id: String { city }
  }

  enum Phase: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  private(set) var visits: [Loci_Travelhistory_VisitedPOI] = []
  private(set) var total: Int32 = 0
  private(set) var phase = Phase.idle
  /// The last failed removal, for the screen to show; cleared by the next try.
  var error: String?
  private var page: Int32 = 0

  private let service: VisitedPlacesService

  init(service: VisitedPlacesService = ConnectVisitedPlacesService()) { self.service = service }

  var canLoadMore: Bool { Int32(visits.count) < total }

  /// Cities ordered by their latest visit, places newest first within each.
  var grouped: [CityVisits] { Self.group(visits) }

  func load() async {
    if visits.isEmpty { phase = .loading }
    do {
      let first = try await service.visitedPOIs(page: 1)
      visits = first.pois
      total = first.total
      page = 1
      phase = .loaded
    } catch {
      phase = visits.isEmpty ? .failed(error.localizedDescription) : .loaded
    }
  }

  func loadMore() async {
    guard canLoadMore, phase == .loaded else { return }
    do {
      let next = try await service.visitedPOIs(page: page + 1)
      page += 1
      visits += next.pois
      total = next.total
      // A short page means the server has nothing more, whatever total said.
      if next.pois.isEmpty { total = Int32(visits.count) }
    } catch {
      // Keep what is shown; the next scroll retries.
    }
  }

  /// Removes a visit at once and puts it back if the server refuses.
  func delete(_ id: String) async {
    guard let index = visits.firstIndex(where: { $0.id == id }) else { return }
    error = nil
    let removed = visits.remove(at: index)
    total = max(total - 1, 0)
    do {
      _ = try await service.deleteVisitedPOI(id: id)
    } catch {
      visits.insert(removed, at: min(index, visits.count))
      total += 1
      self.error = error.userMessage
    }
  }

  nonisolated static func group(_ visits: [Loci_Travelhistory_VisitedPOI]) -> [CityVisits] {
    let sorted = visits.sorted { $0.visitedAt.date > $1.visitedAt.date }
    var order: [String] = []
    var byCity: [String: [Loci_Travelhistory_VisitedPOI]] = [:]
    for visit in sorted {
      let city = visit.cityName.trimmingCharacters(in: .whitespaces).isEmpty ? "Other places" : visit.cityName
      if byCity[city] == nil { order.append(city) }
      byCity[city, default: []].append(visit)
    }
    return order.map { CityVisits(city: $0, places: byCity[$0] ?? []) }
  }
}
