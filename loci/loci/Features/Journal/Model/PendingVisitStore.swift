import CoreLocation
import Foundation
import LociConnectProto

/// A place a visit could have been to: a stop on today's plan or a saved place.
nonisolated struct VisitCandidate: Codable, Sendable, Equatable {
  var poiID: String
  var name: String
  var cityName: String
  var latitude: Double
  var longitude: Double

  var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

/// Which known place a stay was at. Today's stops are checked before saved
/// places: the plan is the likelier reason to be there.
nonisolated enum VisitMatch {
  static let radius: CLLocationDistance = 75

  static func nearest(
    to coordinate: CLLocationCoordinate2D,
    stops: [VisitCandidate],
    favorites: [VisitCandidate],
    within radius: CLLocationDistance = radius,
  ) -> VisitCandidate? {
    let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    func closest(_ places: [VisitCandidate]) -> VisitCandidate? {
      places
        .map { ($0, $0.location.distance(from: here)) }
        .filter { $0.1 <= radius }
        .min { $0.1 < $1.1 }?.0
    }
    return closest(stops) ?? closest(favorites)
  }

  /// The day's stops that carry a place with coordinates.
  static func candidates(stops: [Loci_Trip_TripStop], city: String) -> [VisitCandidate] {
    stops.compactMap { stop in
      guard stop.hasPoi, stop.poi.latitude != 0 || stop.poi.longitude != 0 else { return nil }
      let id = stop.poiID.isEmpty ? stop.poi.id : stop.poiID
      guard !id.isEmpty else { return nil }
      return VisitCandidate(poiID: id, name: stop.name, cityName: city, latitude: stop.poi.latitude, longitude: stop.poi.longitude)
    }
  }

  /// Saved places (not hotels' or itineraries' rows) in `city`.
  static func candidates(favorites: [Loci_Favorites_V1_FavoriteItem], city: String) -> [VisitCandidate] {
    favorites.compactMap { item in
      guard item.contentType != .itinerary, item.cityName.caseInsensitiveCompare(city) == .orderedSame,
        item.latitude != 0 || item.longitude != 0
      else { return nil }
      return VisitCandidate(poiID: item.itemID, name: item.itemName, cityName: item.cityName, latitude: item.latitude, longitude: item.longitude)
    }
  }
}

/// A stay iOS noticed on a trip day that matched a known place, waiting for
/// the traveller to say whether they were there. Nothing is logged without a yes.
nonisolated struct PendingVisit: Codable, Sendable, Equatable, Identifiable {
  var id: String
  var place: VisitCandidate
  var tripID: String
  var arrival: Date
  /// Where the phone was, and how sure it was.
  var latitude: Double
  var longitude: Double
  var accuracy: Double

  /// RecordVisit as an on-the-spot visit: the stay's own position, at its arrival time.
  var request: Loci_Travelhistory_RecordVisitRequest {
    let spot = SpotVisit(
      poiID: place.poiID,
      poiName: place.name,
      cityName: place.cityName,
      latitude: place.latitude,
      longitude: place.longitude,
      tripID: tripID,
    )
    let fix = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      altitude: 0,
      horizontalAccuracy: accuracy,
      verticalAccuracy: -1,
      timestamp: arrival,
    )
    return ProgressAPI.visitRequest(spot, at: fix)
  }
}

/// Sends a confirmed visit.
protocol VisitRecorder: Sendable {
  func record(_ request: Loci_Travelhistory_RecordVisitRequest) async throws
}

nonisolated struct ConnectVisitRecorder: VisitRecorder {
  private static let client = Loci_Travelhistory_TravelHistoryServiceClient(client: ConnectTransport.shared.protocolClient)

  func record(_ request: Loci_Travelhistory_RecordVisitRequest) async throws {
    _ = try await rpc("Could not record the visit.", request) { await Self.client.recordVisit(request: $0, headers: [:]) }
  }
}

/// Visits waiting for a yes or no, kept on the phone so none is lost when the
/// app is killed between the stay and the answer. A week unanswered drops it.
nonisolated struct PendingVisitStore: @unchecked Sendable {
  static let key = "loci_pending_visits"
  static let keep: TimeInterval = 7 * 24 * 3600

  var defaults: UserDefaults = .standard
  var calendar: Calendar = .current

  func all(now: Date = Date()) -> [PendingVisit] {
    let stored = (defaults.data(forKey: Self.key)).flatMap { try? JSONDecoder().decode([PendingVisit].self, from: $0) } ?? []
    let fresh = stored.filter { now.timeIntervalSince($0.arrival) < Self.keep }
    if fresh.count != stored.count { save(fresh) }
    return fresh
  }

  func visits(tripID: String, now: Date = Date()) -> [PendingVisit] {
    all(now: now).filter { $0.tripID == tripID }.sorted { $0.arrival < $1.arrival }
  }

  func visit(id: String, now: Date = Date()) -> PendingVisit? { all(now: now).first { $0.id == id } }

  /// Keeps the visit unless the same place is already waiting for that day.
  @discardableResult func add(_ visit: PendingVisit, now: Date = Date()) -> Bool {
    var visits = all(now: now)
    let duplicate = visits.contains {
      $0.place.poiID == visit.place.poiID && calendar.isDate($0.arrival, inSameDayAs: visit.arrival)
    }
    guard !duplicate else { return false }
    visits.append(visit)
    save(visits)
    return true
  }

  func dismiss(id: String) { save(all().filter { $0.id != id }) }

  /// Records the visit, then forgets it. A failure keeps it for another try.
  func confirm(id: String, recorder: any VisitRecorder = ConnectVisitRecorder(), now: Date = Date()) async throws {
    guard let visit = visit(id: id, now: now) else { return }
    try await recorder.record(visit.request)
    dismiss(id: id)
  }

  private func save(_ visits: [PendingVisit]) {
    if let data = try? JSONEncoder().encode(visits) { defaults.set(data, forKey: Self.key) }
  }
}
