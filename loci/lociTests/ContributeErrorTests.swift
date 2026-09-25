import Connect
import CoreLocation
import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Follow-ups from the review of #35: plain wording for server refusals, a
/// confirm that cannot be retried says why, a midnight close, and the City
/// field winning over the located city.
struct ContributeErrorTests {
  private func error(_ code: Code, _ message: String) -> ContributeError {
    ContributeError(ConnectError(code: code, message: message, exception: nil, details: [], metadata: [:]), fallback: "Fallback.")
  }

  @Test func alreadyOnTheGuideNamesThePlaceAndCannotRetry() {
    let e = error(.alreadyExists, "\"Café Central\" is already on the guide (3f2a9c1e-0000-4000-8000-000000000000)")
    #expect(e.kind == .alreadyOnGuide(name: "Café Central"))
    #expect(e.message(for: .addPlace) == "“Café Central” is already on the guide. Search for it above.")
    #expect(!e.canRetry)
  }

  @Test func failedPreconditionKeepsTheServersReasonAndCannotRetry() {
    let e = error(.failedPrecondition, "no coordinates for this place yet, so it cannot go on the guide yet")
    #expect(e.kind == .notYet("no coordinates for this place yet, so it cannot go on the guide yet"))
    #expect(e.message(for: .confirm) == "No coordinates for this place yet, so it cannot go on the guide yet.")
    #expect(!e.canRetry)
  }

  @Test func unimplementedInvalidNotFoundAndOfflineReadAsPlainWording() {
    #expect(
      error(.unimplemented, "city resolution is not configured").message(for: .addPlace) == "Contributions are switched off right now. Try later."
    )
    #expect(
      error(.invalidArgument, "could not place \"Foo\" in a city: no match").message(for: .addPlace)
        == "We couldn't place that in a city. Check the city name."
    )
    #expect(error(.notFound, "unknown place").message(for: .report) == "That place isn't on the guide any more.")
    let offline = error(.unavailable, "dial tcp: connection refused")
    #expect(offline.message(for: .report) == "You're offline. Try again when you're back online.")
    #expect(offline.canRetry)
  }

  @Test func anythingElseFallsBackToTheActionsOwnWording() {
    #expect(error(.internalError, "boom").message(for: .confirm) == "That did not go through. Try again.")
    #expect(error(.internalError, "boom").message(for: .report) == "Could not file the report. Try again.")
  }

  @Test func wrapsAnyErrorSoStoresNeverShowRawText() {
    struct Plain: Error {}
    #expect(ContributeError.message(from: Plain(), for: .addPlace) == "Could not add this place. Try again.")
    #expect(ContributeError.message(from: error(.notFound, "unknown place"), for: .report) == "That place isn't on the guide any more.")
  }
}

struct OpeningHoursMidnightTests {
  @Test func aCloseAtMidnightBecomesTwentyFour() {
    var week = OpeningHours.default
    week.setTime(.mon, start: false, to: "00:00")
    #expect(week.encoded.hasPrefix("mon 09:00-24:00"))
    #expect(week.isValid)
  }

  @Test func anOpenAtMidnightStaysZero() {
    var week = OpeningHours.default
    week.setTime(.mon, start: true, to: "00:00")
    #expect(week.encoded.hasPrefix("mon 00:00-17:00"))
  }

  @Test func saysWhyADayIsInvalid() {
    var week = OpeningHours.default
    #expect(week.problem(.mon) == nil)
    #expect(week.problem(.sat) == nil)
    week.setTime(.mon, start: false, to: "08:00")
    #expect(week.problem(.mon) == "Closes before it opens. Past-midnight hours aren't supported yet.")
  }
}

struct ContributeSearchCityTests {
  private let lisbon = ContributeSearchContext(coordinate: CLLocationCoordinate2D(latitude: 38.72, longitude: -9.14), city: "Lisbon")

  @Test func aTypedCityThatDiffersFromTheLocatedOneSearchesThatCity() {
    #expect(ContributePayload.searchCoordinate(typedCity: "Porto", context: lisbon) == nil)
    let coordinate = ContributePayload.searchCoordinate(typedCity: "Porto", context: lisbon)
    let request = ContributePayload.search(query: "cafe", city: "Porto", coordinate: coordinate)
    #expect(request?.searchType == "semantic")
    #expect(request?.cityName == "Porto")
  }

  @Test func theLocatedCityOrAnEmptyFieldKeepsTheNearbySearch() {
    #expect(ContributePayload.searchCoordinate(typedCity: " lisbon ", context: lisbon) != nil)
    #expect(ContributePayload.searchCoordinate(typedCity: "", context: lisbon) != nil)
    #expect(ContributePayload.searchCoordinate(typedCity: "Porto", context: nil) == nil)
  }
}

@MainActor
struct ClaimFormResubmitTests {
  private struct Once: ContributeService {
    func tasks() async throws -> [VerificationTask] { [] }
    func profile() async throws -> ContributorProfile { .empty }
    func pendingPlaces() async throws -> [PendingPlace] { [] }
    func submitClaims(poiID: String, field: Loci_Place_PlaceFactField, values: [String]) async throws -> ClaimResult {
      try await PreviewContributeService().submitClaims(poiID: poiID, field: field, values: values)
    }
    func submitPlace(_ draft: PlaceDraft) async throws -> PlaceSubmissionResult { try await PreviewContributeService().submitPlace(draft) }
    func confirmPlace(submissionID: String) async throws -> PlaceSubmissionResult { try await PreviewContributeService().confirmPlace(submissionID: submissionID) }
    func searchPlaces(query: String, city: String, coordinate: CLLocationCoordinate2D?) async throws -> [Loci_Poi_POIDetailedInfo] { [] }
    func searchContext() async -> ContributeSearchContext? { nil }
  }

  @Test func openingHoursCannotBeFiledTwiceUnchanged() async {
    let task = VerificationTask(poiID: "poi-1", poiName: "Café", requestedFields: [.openingHours])
    let store = ClaimFormStore(task: task, service: Once(), field: .openingHours)
    #expect(store.isReady)
    await store.submit()
    #expect(store.result != nil)
    #expect(!store.isReady)
    store.hours.setTime(.mon, start: false, to: "18:00")
    #expect(store.isReady)
    #expect(store.result == nil)
  }
}
