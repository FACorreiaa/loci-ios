import Foundation
import LociConnectProto

/// Planning together's comments (web: lib/api/trip-comments.ts): notes the
/// owner and members leave on a trip or one of its stops.
nonisolated enum TripCommentsAPI {
  private static var client: Loci_Trip_TripServiceClient { TripAPI.client }

  /// The reasons a comment can be reported for, as the server spells them.
  static let reportReasons: [(value: String, label: String)] = [
    ("spam", "Spam"), ("inappropriate", "Inappropriate"), ("offensive", "Offensive"), ("other", "Something else"),
  ]

  /// The trip's latest comments, oldest first, for anyone on it.
  static func list(tripID: String) async throws -> [Loci_Trip_TripComment] {
    var request = Loci_Trip_ListTripCommentsRequest()
    request.tripID = tripID
    return try await rpc("Could not load the comments.", request) { await client.listTripComments(request: $0, headers: [:]) }.comments
  }

  /// A comment about the trip, or about one of its stops.
  static func add(tripID: String, body: String, stopID: String?) async throws -> Loci_Trip_TripComment {
    var request = Loci_Trip_AddTripCommentRequest()
    request.tripID = tripID
    request.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
    request.stopID = stopID ?? ""
    return try await rpc("Couldn't post that comment.", request) { await client.addTripComment(request: $0, headers: [:]) }
  }

  /// Its author or the trip's owner.
  static func delete(commentID: String) async throws {
    var request = Loci_Trip_DeleteTripCommentRequest()
    request.commentID = commentID
    _ = try await rpc("Couldn't delete that comment.", request) { await client.deleteTripComment(request: $0, headers: [:]) }
  }

  /// Hides the comment from the reporter at once and flags it for review.
  static func report(commentID: String, reason: String) async throws {
    var request = Loci_Trip_ReportTripCommentRequest()
    request.commentID = commentID
    request.reason = reason
    _ = try await rpc("Couldn't report that comment.", request) { await client.reportTripComment(request: $0, headers: [:]) }
  }
}
