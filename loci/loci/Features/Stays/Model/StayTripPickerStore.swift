import Foundation
import LociConnectProto
import Observation

/// "Which trip?" for a hotel from a comparison report: lists the caller's
/// trips, and sets the stay on the one they tap against a version read the
/// moment before (see `AddStayFlow`).
@MainActor @Observable final class StayTripPickerStore {
  enum Phase: Equatable {
    case loading, loaded
    case failed(String)
  }

  let stay: Loci_Trip_TripStay
  let hotelName: String
  private(set) var options: [StayTripOption] = []
  private(set) var phase = Phase.loading
  private(set) var addingTripID: String?
  /// Set once the hotel is a trip's stay; the sheet then offers "Open trip".
  private(set) var added: Loci_Trip_TripDraft?
  var error: String?

  private let service: StayService

  init(stay: Loci_Trip_TripStay, hotelName: String, service: StayService = ConnectStayService()) {
    self.stay = stay
    self.hotelName = hotelName
    self.service = service
  }

  var cityName: String { stay.cityName }
  var hasEligibleTrip: Bool { options.contains(where: \.isEligible) }

  func load() async {
    do {
      options = StayTripPicker.options(try await service.trips(), city: cityName)
      phase = .loaded
    } catch {
      guard !error.isCancellation else { return }
      phase = .failed(error.userMessage)
    }
  }

  /// Make the hotel this trip's stay. True once it is.
  @discardableResult func add(to tripID: String) async -> Bool {
    guard addingTripID == nil, added == nil, options.contains(where: { $0.id == tripID && $0.isEligible }) else { return false }
    addingTripID = tripID
    defer { addingTripID = nil }
    do {
      added = try await AddStayFlow.set(stay, tripID: tripID, service: service)
      return true
    } catch {
      guard !error.isCancellation else { return false }
      // The city went from the trip meanwhile: show the list as it now is.
      if error is AddStayError { await load() }
      self.error = error.userMessage
      return false
    }
  }
}
