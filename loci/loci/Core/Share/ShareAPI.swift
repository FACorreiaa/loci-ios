import Connect
import Foundation
import LociConnectProto

/// ShareService (loci.share), web: lib/api/share.ts.
nonisolated enum ShareAPI {
  private static let client = Loci_Share_ShareServiceClient(client: ConnectTransport.shared.protocolClient)
  private static let itineraries = Loci_Itinerary_ItineraryServiceClient(client: ConnectTransport.shared.protocolClient)

  /// web: createShareLink. The server's URL when it sends one, else ours from the code.
  static func createLink(target: ShareTarget, userID: String?) async throws -> URL {
    var request = Loci_Share_CreateShareLinkRequest()
    request.userID = userID ?? ""
    request.contentType = target.contentType
    request.contentID = target.contentID
    request.title = target.title
    let response = try await rpc("Could not make a link for this.", request) { await client.createShareLink(request: $0, headers: [:]) }
    guard response.success else { throw APIError.custom(response.message.isEmpty ? "Could not make a link for this." : response.message) }
    if let url = URL(string: response.shareURL), url.scheme != nil { return url }
    guard let url = ShareLinks.share(code: response.shareCode) else { throw APIError.invalidResponse }
    return url
  }

  /// web: getSharedContent. A dead code is NotFound.
  static func sharedContent(code: String) async throws -> Loci_Share_SharedContent {
    var request = Loci_Share_GetSharedContentRequest()
    request.shareCode = code
    let response = try await rpc("Could not open this link.", request) { await client.getSharedContent(request: $0, headers: [:]) }
    guard response.success, response.hasContent else {
      throw APIError.notFound(response.message.isEmpty ? "This link has expired." : response.message)
    }
    return response.content
  }

  /// A shared itinerary opens the saved-itinerary page by id (ItineraryService.GetItinerary).
  static func itinerary(id: String) async throws -> Loci_Itinerary_UserSavedItinerary {
    var request = Loci_Itinerary_GetItineraryRequest()
    request.itineraryID = id
    let response = try await rpc("Could not load this itinerary.", request) { await itineraries.getItinerary(request: $0, headers: [:]) }
    guard response.hasItinerary else { throw APIError.notFound("This itinerary is no longer available.") }
    return response.itinerary
  }
}
