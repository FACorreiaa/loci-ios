import Foundation
import LociConnectProto
import Observation

/// Add to trip, from a place's detail (web: AddToTripButton). Picks a trip
/// (the first by default) and a day (its first), and adds against a version
/// read the moment before (see `AddToTripFlow`).
@MainActor @Observable final class AddToTripStore {
  enum Phase: Equatable {
    case loading, loaded
    case failed(String)
  }

  let poi: Loci_Poi_POIDetailedInfo
  let cityName: String
  private(set) var trips: [Loci_Trip_TripDraft] = []
  private(set) var phase = Phase.loading
  private(set) var isAdding = false
  private(set) var isCreating = false
  /// Set once the place is in a trip; the sheet then offers "Open trip".
  private(set) var added: AddedStop?
  var error: String?

  var selectedTripID: String? {
    didSet { if oldValue != selectedTripID { selectedDayNumber = selectedTrip?.days.first?.dayNumber } }
  }

  /// By number, not id: the server gives every day a new id on each save.
  var selectedDayNumber: Int32?

  private let service: AddToTripService

  init(poi: Loci_Poi_POIDetailedInfo, cityName: String, service: AddToTripService = ConnectAddToTripService()) {
    self.poi = poi
    self.cityName = cityName
    self.service = service
  }

  var placeName: String { TripStopBuilder.name(for: poi) }
  var selectedTrip: Loci_Trip_TripDraft? { trips.first { $0.id == selectedTripID } }
  var selectedDay: Loci_Trip_TripDay? { selectedTrip?.days.first { $0.dayNumber == selectedDayNumber } }
  var canAdd: Bool { selectedDay != nil && !isAdding && !isCreating }
  /// The city a new trip would be for: the page's, else the place's own.
  var newTripCity: String { cityName.isEmpty ? poi.city : cityName }

  func load() async {
    do {
      trips = try await service.trips()
      phase = .loaded
      if selectedTrip == nil { selectedTripID = trips.first?.id }
    } catch {
      guard !error.isCancellation else { return }
      phase = .failed(error.userMessage)
    }
  }

  /// Add to the chosen day. True once the place is in.
  @discardableResult func add() async -> Bool {
    guard canAdd, let tripID = selectedTripID, let dayNumber = selectedDayNumber else { return false }
    isAdding = true
    defer { isAdding = false }
    do {
      let result = try await AddToTripFlow.add(poi, tripID: tripID, dayNumber: dayNumber, service: service)
      adopt(result.trip)
      added = result
      Analytics.capture(.tripStopAdded, ["source": "place_detail"])
      return true
    } catch {
      guard !error.isCancellation else { return false }
      if (error as? AddToTripError) == .dayMissing { await load() }
      self.error = error.userMessage
      return false
    }
  }

  /// No trips yet: a new one for this city with the place on Day 1.
  @discardableResult func createTrip(userID: String?) async -> Bool {
    guard !isCreating, !isAdding else { return false }
    isCreating = true
    defer { isCreating = false }
    do {
      let trip = try await service.createTrip(AddToTripPayload.newTrip(for: poi, cityName: newTripCity, userID: userID))
      trips.insert(trip, at: 0)
      selectedTripID = trip.id
      added = AddedStop(trip: trip, dayNumber: trip.days.first?.dayNumber ?? 1)
      Analytics.capture(.tripStopAdded, ["source": "place_detail", "new_trip": true])
      return true
    } catch {
      guard !error.isCancellation else { return false }
      self.error = error.userMessage
      return false
    }
  }

  /// Keep the list's copy current, so the day rows show the new stop count.
  private func adopt(_ trip: Loci_Trip_TripDraft) {
    guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
    trips[index] = trip
  }
}
