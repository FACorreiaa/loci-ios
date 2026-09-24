import Foundation
import LociConnectProto

/// What the trip checklists need from TripService. Behind a protocol so the
/// store's optimistic edits and rollbacks run in tests and design previews.
nonisolated protocol TripChecklistService: Sendable {
  func checklist(tripID: String) async throws(TripRPCError) -> Loci_Trip_GetTripChecklistResponse
  func suggestions(tripID: String) async throws(TripRPCError) -> Loci_Trip_SuggestPackingResponse
  func upsert(tripID: String, item: Loci_Trip_ChecklistItem) async throws(TripRPCError) -> Loci_Trip_ChecklistItem
  func delete(tripID: String, itemID: String) async throws(TripRPCError)
  func dismiss(tripID: String, text: String) async throws(TripRPCError)
}

/// The live service over the app's authenticated transport.
nonisolated struct ConnectTripChecklistService: TripChecklistService {
  func checklist(tripID: String) async throws(TripRPCError) -> Loci_Trip_GetTripChecklistResponse {
    try await TripAPI.checklist(tripID: tripID)
  }

  func suggestions(tripID: String) async throws(TripRPCError) -> Loci_Trip_SuggestPackingResponse {
    try await TripAPI.suggestPacking(tripID: tripID)
  }

  func upsert(tripID: String, item: Loci_Trip_ChecklistItem) async throws(TripRPCError) -> Loci_Trip_ChecklistItem {
    try await TripAPI.upsertChecklistItem(tripID: tripID, item: item)
  }

  func delete(tripID: String, itemID: String) async throws(TripRPCError) {
    try await TripAPI.deleteChecklistItem(tripID: tripID, itemID: itemID)
  }

  func dismiss(tripID: String, text: String) async throws(TripRPCError) {
    try await TripAPI.dismissPackingSuggestion(tripID: tripID, text: text)
  }
}

/// An in-memory service for design previews: every write succeeds.
nonisolated struct PreviewTripChecklistService: TripChecklistService {
  var checklist = Loci_Trip_GetTripChecklistResponse()
  var packing = Loci_Trip_SuggestPackingResponse()

  func checklist(tripID: String) async throws(TripRPCError) -> Loci_Trip_GetTripChecklistResponse { checklist }
  func suggestions(tripID: String) async throws(TripRPCError) -> Loci_Trip_SuggestPackingResponse { packing }
  func upsert(tripID: String, item: Loci_Trip_ChecklistItem) async throws(TripRPCError) -> Loci_Trip_ChecklistItem { item }
  func delete(tripID: String, itemID: String) async throws(TripRPCError) {}
  func dismiss(tripID: String, text: String) async throws(TripRPCError) {}
}
