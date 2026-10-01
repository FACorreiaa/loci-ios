import Connect
import Foundation
import LociConnectProto

/// ReviewService (loci.review), one static func per RPC. Web's /reviews is
/// mostly a mock, so the `web:` notes name the hook it has, where it has one.
nonisolated enum ReviewsAPI {
  private static let client = Loci_Review_ReviewServiceClient(client: ConnectTransport.shared.protocolClient)
  private static let poi = Loci_Poi_PoiserviceClient(client: ConnectTransport.shared.protocolClient)

  /// web: none (the mock page computes its own). Count, average, 1–5 breakdown.
  static func statistics(poiID: String) async throws -> ReviewStats {
    let response = try await reviewRPC("Could not load the rating summary.", ReviewPayload.statistics(poiID: poiID)) {
      await client.getReviewStatistics(request: $0, headers: [:])
    }
    return response.hasStatistics ? ReviewStats(response.statistics) : .empty
  }

  /// web: usePOIReviews → GetPOIReviews{poiId, pagination}. Newest first.
  static func poiReviews(poiID: String, page: Int) async throws -> ReviewPage {
    let response = try await reviewRPC("Could not load reviews.", ReviewPayload.poiReviews(poiID: poiID, page: page)) {
      await client.getPoireviews(request: $0, headers: [:])
    }
    return ReviewPage(reviews: response.reviews, pagination: response.hasPagination ? response.pagination : nil)
  }

  /// web: useUserReviews → GetUserReviews with no user id (the caller's).
  static func myReviews(page: Int, pageSize: Int32 = ReviewPayload.pageSize) async throws -> ReviewPage {
    let request = ReviewPayload.userReviews(page: page, pageSize: pageSize)
    let response = try await reviewRPC("Could not load your reviews.", request) { await client.getUserReviews(request: $0, headers: [:]) }
    return ReviewPage(response)
  }

  /// web: fetchMyPOIReview → GetMyPOIReview{poiId}. Nil when you have none
  /// (NotFound). A server without the RPC (Unimplemented) is asked the old
  /// way: your reviews, 100 at a time, filtered by place.
  static func myPOIReview(poiID: String) async throws -> LociReview? {
    let request = ReviewPayload.myPOIReview(poiID: poiID)
    let response = await withAuthRetry { await client.getMyPoireview(request: request, headers: [:]) }
    switch ReviewPayload.ownLookup(response.error?.code) {
    case .answered:
      guard let message = response.message, message.hasReview else { return nil }
      return LociReview(message.review)
    case .noReview:
      return nil
    case .scan:
      return try await ReviewPayload.scanForOwn(poiID: poiID) { page in
        try await myReviews(page: page, pageSize: ReviewPayload.ownLookupPageSize)
      }
    case .failed:
      throw APIError(connect: response.error, fallback: "Could not check for your review.")
    }
  }

  /// web: useReportReview → ReportReview{reviewId, reason, details}. Your own
  /// review (PermissionDenied) and a review that can't take a report
  /// (FailedPrecondition) come back as one plain sentence.
  static func report(reviewID: String, reason: ReviewReport.Reason, details: String = "") async throws {
    let request = ReviewPayload.report(reviewID: reviewID, reason: reason, details: details)
    let response = await withAuthRetry { await client.reportReview(request: request, headers: [:]) }
    if let refusal = ReviewReport.refusal(response.error?.code) { throw APIError.custom(refusal) }
    _ = try response.unwrap("Could not send your report.")
  }

  /// web: useCreateReviewMutation. A second review of the same place is
  /// AlreadyExists, which arrives as `APIError.conflict`.
  static func create(poiID: String, form: ReviewForm) async throws -> LociReview {
    guard let request = ReviewPayload.create(poiID: poiID, form: form) else { throw APIError.custom("This place can't be reviewed yet.") }
    let response = try await reviewRPC("Could not post your review.", request) { await client.createReview(request: $0, headers: [:]) }
    return LociReview(response.review)
  }

  /// web: none. Owner-only on the server (someone else's review is NotFound).
  static func update(reviewID: String, form: ReviewForm) async throws -> LociReview {
    guard let request = ReviewPayload.update(reviewID: reviewID, form: form) else { throw APIError.custom("Check the review and try again.") }
    let response = try await reviewRPC("Could not save your review.", request) { await client.updateReview(request: $0, headers: [:]) }
    return LociReview(response.review)
  }

  /// web: useDeleteReviewMutation. Owner-only.
  static func delete(reviewID: String) async throws {
    _ = try await reviewRPC("Could not delete the review.", ReviewPayload.delete(reviewID: reviewID)) {
      await client.deleteReview(request: $0, headers: [:])
    }
  }

  /// web: useLikeReviewMutation (which always sends true). Returns the new helpful count.
  static func like(reviewID: String, isLike: Bool) async throws -> Int {
    let response = try await reviewRPC("Could not record your vote.", ReviewPayload.like(reviewID: reviewID, isLike: isLike)) {
      await client.likeReview(request: $0, headers: [:])
    }
    return Int(max(0, response.newHelpfulCount))
  }

  /// The reviewed place, for opening it from My reviews (PoiService.GetPOI,
  /// as the saved-place and list pages do). Nil when it can't be loaded.
  static func place(poiID: String) async -> Loci_Poi_POIDetailedInfo? {
    guard ReviewPayload.canReview(poiID: poiID) else { return nil }
    var request = Loci_Poi_GetPOIRequest()
    request.poiID = poiID
    guard let response = try? await rpc("Could not load this place.", request, { await poi.getPoi(request: $0, headers: [:]) }), response.hasPoi
    else { return nil }
    return response.poi
  }

  /// `rpc` with a 501 in plain words, as ListsAPI does.
  private static func reviewRPC<Input: Sendable, Output>(
    _ fallback: String,
    _ request: Input,
    _ call: @Sendable (Input) async -> ResponseMessage<Output>
  ) async throws -> Output {
    let response = await withAuthRetry { await call(request) }
    if response.error?.code == .unimplemented { throw APIError.custom("\(fallback) This isn't available on the server yet.") }
    return try response.unwrap(fallback)
  }
}

/// What the review screens need from the server, behind a protocol so the
/// design previews and tests run without a session.
nonisolated protocol ReviewsService: Sendable {
  /// Whose reviews are "yours" (edit/delete instead of a helpful vote).
  func currentUserID() async -> String?
  func statistics(poiID: String) async throws -> ReviewStats
  func placeReviews(poiID: String, page: Int) async throws -> ReviewPage
  func myReviews(page: Int) async throws -> ReviewPage
  /// The caller's review of one place, if any (GetMyPOIReview).
  func ownReview(poiID: String) async throws -> LociReview?
  func create(poiID: String, form: ReviewForm) async throws -> LociReview
  func update(reviewID: String, form: ReviewForm) async throws -> LociReview
  func delete(reviewID: String) async throws
  func like(reviewID: String, isLike: Bool) async throws -> Int
  /// Flag someone else's review for the Loci team.
  func report(reviewID: String, reason: ReviewReport.Reason) async throws
}

nonisolated struct ConnectReviewsService: ReviewsService {
  func currentUserID() async -> String? { await AuthSessionManager.shared.currentUserID }
  func statistics(poiID: String) async throws -> ReviewStats { try await ReviewsAPI.statistics(poiID: poiID) }
  func placeReviews(poiID: String, page: Int) async throws -> ReviewPage { try await ReviewsAPI.poiReviews(poiID: poiID, page: page) }
  func myReviews(page: Int) async throws -> ReviewPage { try await ReviewsAPI.myReviews(page: page) }

  func ownReview(poiID: String) async throws -> LociReview? { try await ReviewsAPI.myPOIReview(poiID: poiID) }

  func create(poiID: String, form: ReviewForm) async throws -> LociReview { try await ReviewsAPI.create(poiID: poiID, form: form) }
  func update(reviewID: String, form: ReviewForm) async throws -> LociReview { try await ReviewsAPI.update(reviewID: reviewID, form: form) }
  func delete(reviewID: String) async throws { try await ReviewsAPI.delete(reviewID: reviewID) }
  func like(reviewID: String, isLike: Bool) async throws -> Int { try await ReviewsAPI.like(reviewID: reviewID, isLike: isLike) }
  func report(reviewID: String, reason: ReviewReport.Reason) async throws { try await ReviewsAPI.report(reviewID: reviewID, reason: reason) }
}
