import Connect
import Foundation
import LociConnectProto

/// A TripService failure that keeps its Connect code, because the trip page
/// acts on the code: a version conflict reloads, an unknown RPC (the server
/// not deployed yet) hides the checklists instead of raising an alert.
nonisolated struct TripRPCError: LocalizedError, Equatable, Sendable {
  let code: Code?
  let message: String

  /// The server refused an edit made against an older `version`
  /// (`ErrVersionConflict` → FailedPrecondition; Aborted is Connect's other
  /// conflict code and is treated the same).
  var isVersionConflict: Bool { code == .failedPrecondition || code == .aborted }

  /// The RPC does not exist on this server yet. Connect answers an unknown
  /// route with Unimplemented (an HTTP 404 maps there too).
  var isUnimplemented: Bool { code == .unimplemented }

  /// Canceled by the view going away; never shown.
  var isCancelled: Bool { code == .canceled }

  var errorDescription: String? { message }

  init(code: Code?, message: String) {
    self.code = code
    self.message = message
  }

  init(_ error: ConnectError?, fallback: String) {
    code = error?.code
    let apiError = APIError(connect: error, fallback: fallback)
    message = apiError.errorDescription ?? fallback
  }
}

/// The trip client, shared by the list, the editor and Compare's save, plus one
/// static func per RPC the trip page calls.
nonisolated enum TripAPI {
  static let client = Loci_Trip_TripServiceClient(client: ConnectTransport.shared.protocolClient)

  /// `rpc`, but the thrown error keeps its Connect code.
  static func call<Input: Sendable, Output>(
    _ fallback: String,
    _ request: Input,
    _ call: @Sendable (Input) async -> ResponseMessage<Output>
  ) async throws(TripRPCError) -> Output {
    let response = await withAuthRetry { await call(request) }
    if let message = response.message { return message }
    throw TripRPCError(response.error, fallback: fallback)
  }

  /// web: lib/api/trips.ts useTrip → GetTrip{tripId}
  static func trip(id: String) async throws(TripRPCError) -> Loci_Trip_TripDraft {
    var request = Loci_Trip_GetTripRequest()
    request.tripID = id
    return try await call("Could not load the trip.", request) { await client.getTrip(request: $0, headers: [:]) }
  }

  /// web: lib/api/packing.ts useSuggestPacking → SuggestPacking{tripId}
  static func suggestPacking(tripID: String) async throws(TripRPCError) -> Loci_Trip_SuggestPackingResponse {
    var request = Loci_Trip_SuggestPackingRequest()
    request.tripID = tripID
    return try await call("Could not suggest packing.", request) { await client.suggestPacking(request: $0, headers: [:]) }
  }

  /// web: (Phase 8 move of TripChecklists) → GetTripChecklist{tripId}
  static func checklist(tripID: String) async throws(TripRPCError) -> Loci_Trip_GetTripChecklistResponse {
    var request = Loci_Trip_GetTripChecklistRequest()
    request.tripID = tripID
    return try await call("Could not load the checklists.", request) { await client.getTripChecklist(request: $0, headers: [:]) }
  }

  /// web: (Phase 8) → UpsertChecklistItem{tripId, item}; idempotent on item.id.
  static func upsertChecklistItem(tripID: String, item: Loci_Trip_ChecklistItem) async throws(TripRPCError) -> Loci_Trip_ChecklistItem {
    var request = Loci_Trip_UpsertChecklistItemRequest()
    request.tripID = tripID
    request.item = item
    return try await call("Could not save that item.", request) { await client.upsertChecklistItem(request: $0, headers: [:]) }
  }

  /// web: (Phase 8) → DeleteChecklistItem{tripId, itemId}; a missing item succeeds.
  static func deleteChecklistItem(tripID: String, itemID: String) async throws(TripRPCError) {
    var request = Loci_Trip_DeleteChecklistItemRequest()
    request.tripID = tripID
    request.itemID = itemID
    _ = try await call("Could not remove that item.", request) { await client.deleteChecklistItem(request: $0, headers: [:]) }
  }

  /// web: (Phase 8) → DismissPackingSuggestion{tripId, text}
  static func dismissPackingSuggestion(tripID: String, text: String) async throws(TripRPCError) {
    var request = Loci_Trip_DismissPackingSuggestionRequest()
    request.tripID = tripID
    request.text = text
    _ = try await call("Could not hide that suggestion.", request) { await client.dismissPackingSuggestion(request: $0, headers: [:]) }
  }

  /// web: lib/api/trips.ts exportTrip → ExportTrip{tripId, format}
  static func export(tripID: String, format: Loci_Trip_ExportFormat) async throws(TripRPCError) -> Loci_Trip_ExportTripResponse {
    var request = Loci_Trip_ExportTripRequest()
    request.tripID = tripID
    request.format = format
    return try await call("Could not export the trip.", request) { await client.exportTrip(request: $0, headers: [:]) }
  }

  /// web: routes/trips/[id].tsx share → ShareTrip{tripId, isPublic: true}
  static func share(tripID: String) async throws(TripRPCError) -> Loci_Trip_ShareTripResponse {
    var request = Loci_Trip_ShareTripRequest()
    request.tripID = tripID
    request.isPublic = true
    return try await call("Could not create a share link.", request) { await client.shareTrip(request: $0, headers: [:]) }
  }
}
