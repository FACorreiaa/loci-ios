import CoreLocation
import Foundation
import LociConnectProto

/// Offline sample data for `-designPreview contribute`, `claimForm` and
/// `openingHours`, for "Report a fact" on a place detail shown in a design
/// preview, and for the tests. Writes echo what they were given.
nonisolated struct PreviewContributeService: ContributeService {
  var claimStatus: Loci_Place_PlaceClaimStatus = .pending
  var failTasks = false
  var taskCount = 12

  func tasks() async throws -> [VerificationTask] {
    if failTasks { throw APIError.network("The connection was lost.") }
    return Array(VerificationTask.previewTasks.prefix(taskCount))
  }

  func profile() async throws -> ContributorProfile {
    ContributorProfile(reputation: 42, submittedClaims: 17, acceptedClaims: 11, badges: ["local-scout"])
  }

  func pendingPlaces() async throws -> [PendingPlace] {
    [
      PendingPlace(submissionID: "p-1", name: "Tasca do Chico", cityName: "Lisbon", category: "fado bar", confirmationsNeeded: 1),
      PendingPlace(submissionID: "p-2", name: "Miradouro do Monte Agudo", cityName: "Lisbon", category: "viewpoint", confirmationsNeeded: 1),
    ]
  }

  func submitClaims(poiID: String, field: Loci_Place_PlaceFactField, values: [String]) async throws -> ClaimResult {
    ClaimResult.best(values.map { ClaimResult(claimID: "claim-\($0)", status: claimStatus) })
  }

  func submitPlace(_ draft: PlaceDraft) async throws -> PlaceSubmissionResult {
    PlaceSubmissionResult(submissionID: draft.submissionID, promoted: false, confirmationsNeeded: 1)
  }

  func confirmPlace(submissionID: String) async throws -> PlaceSubmissionResult {
    PlaceSubmissionResult(submissionID: submissionID, promoted: true, confirmationsNeeded: 0)
  }

  func searchPlaces(query: String, city: String, coordinate: CLLocationCoordinate2D?) async throws -> [Loci_Poi_POIDetailedInfo] {
    VerificationTask.previewTasks.prefix(3).map { task in
      var poi = Loci_Poi_POIDetailedInfo()
      poi.id = task.poiID
      poi.name = task.poiName
      poi.category = "cafe"
      poi.city = city.isEmpty ? "Lisbon" : city
      return poi
    }
  }

  func searchContext() async -> ContributeSearchContext? { nil }
}

extension VerificationTask {
  nonisolated static let previewTasks: [VerificationTask] = {
    let names = [
      "Café A Brasileira", "Time Out Market", "Pastéis de Belém", "LX Factory", "Miradouro da Graça", "Cervejaria Ramiro",
      "Fábrica Coffee Roasters", "Jardim da Estrela", "Museu do Azulejo", "Park Bar", "Livraria Bertrand", "Mercado de Campo de Ourique",
    ]
    let fieldSets: [[Loci_Place_PlaceFactField]] = [
      [.openingHours, .priceLevel, .vibe],
      [.crowdLevel, .noiseLevel],
      [.openingHours, .dietary, .accessibility, .childFriendly],
      [.vibe],
    ]
    return names.enumerated().map { index, name in
      VerificationTask(
        poiID: String(format: "5f0c0000-0000-4000-8000-%012d", index + 1),
        poiName: name,
        requestedFields: fieldSets[index % fieldSets.count]
      )
    }
  }()
}
