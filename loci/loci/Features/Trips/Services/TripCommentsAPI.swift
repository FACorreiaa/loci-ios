import Foundation
import LociConnectProto
import SwiftProtobuf

/// Planning together's comments (web: lib/api/trip-comments.ts): notes the
/// owner and members leave on a trip or one of its stops.
nonisolated enum TripCommentsAPI {
  private static var client: Loci_Trip_TripServiceClient { TripAPI.client }

  /// The reasons a comment can be reported for, as the server spells them.
  static let reportReasons: [(value: String, label: String)] = [
    ("spam", "Spam"), ("inappropriate", "Inappropriate"), ("offensive", "Offensive"), ("other", "Something else"),
  ]

  /// A page of the trip's comments, oldest first, for anyone on it: the
  /// latest, or those before `before`. `hasMore` means older ones remain.
  /// `before` is a comment's own created_at, passed through whole: a Date
  /// would round the server's microseconds.
  static func list(tripID: String, before: Google_Protobuf_Timestamp? = nil) async throws -> (comments: [Loci_Trip_TripComment], hasMore: Bool) {
    var request = Loci_Trip_ListTripCommentsRequest()
    request.tripID = tripID
    if let before { request.before = before }
    let response = try await rpc("Could not load the comments.", request) { await client.listTripComments(request: $0, headers: [:]) }
    return (response.comments, response.hasMore_p)
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
