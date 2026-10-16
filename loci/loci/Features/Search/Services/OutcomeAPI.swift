import Foundation
import LociConnectProto
import SwiftProtobuf

/// A traveller's verdict on a place Loci recommended, as a learning event
/// (web: lib/results/outcome.ts). Only places carrying a recommendation trace
/// have one: the server rejects events for recommendations it did not issue.
nonisolated struct Outcome: Sendable, Equatable {
  let type: Loci_Recommendation_RecommendationEventType
  let trace: Loci_Recommendation_RecommendationTrace
  let poiID: String?

  /// The wire event, stamped with the iOS channel and a fresh client id.
  func event(at date: Date = Date()) -> Loci_Recommendation_RecommendationEvent {
    var trace = trace
    trace.channel = .ios
    var event = Loci_Recommendation_RecommendationEvent()
    event.clientEventID = UUID().uuidString.lowercased()
    event.eventType = type
    event.trace = trace
    event.occurredAt = Google_Protobuf_Timestamp(date: date)
    if let poiID, !poiID.isEmpty { event.poiID = poiID }
    return event
  }
}

extension Loci_Poi_POIDetailedInfo {
  /// The outcome for this place, or nil when Loci did not recommend it.
  nonisolated func outcome(_ type: Loci_Recommendation_RecommendationEventType) -> Outcome? {
    guard hasRecommendationTrace, !recommendationTrace.runID.isEmpty else { return nil }
    return Outcome(type: type, trace: recommendationTrace, poiID: id)
  }
}

/// RecommendationService.RecordEvents for outcomes. Fire-and-forget: a lost
/// outcome costs one signal, never the screen it came from.
nonisolated enum OutcomeAPI {
  private static let client = Loci_Recommendation_RecommendationServiceClient(client: ConnectTransport.shared.protocolClient)

  static func record(_ outcomes: [Outcome]) async {
    guard !outcomes.isEmpty else { return }
    var request = Loci_Recommendation_RecordEventsRequest()
    request.events = outcomes.map { $0.event() }
    _ = try? await rpc("Could not record that.", request) { await client.recordEvents(request: $0, headers: [:]) }
  }

  /// Records without making the caller wait.
  static func send(_ outcome: Outcome?) {
    guard let outcome else { return }
    Task.detached { await record([outcome]) }
  }
}
