import Connect
import Foundation
import LociConnectProto

/// ReviewService (loci.review), one static func per RPC. Web's /reviews is
/// mostly a mock, so the `web:` notes name the hook it has, where it has one.
/// ReportReview is Unimplemented on the server and is not wrapped.
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
    return ReviewPage(reviews: response.reviews, pagination: response.hasPagination ? response.pagination : nil)
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
  /// The caller's review of one place, if any (GetUserReviews, filtered).
  func ownReview(poiID: String) async throws -> LociReview?
  func create(poiID: String, form: ReviewForm) async throws -> LociReview
  func update(reviewID: String, form: ReviewForm) async throws -> LociReview
  func delete(reviewID: String) async throws
  func like(reviewID: String, isLike: Bool) async throws -> Int
}

nonisolated struct ConnectReviewsService: ReviewsService {
  func currentUserID() async -> String? { await AuthSessionManager.shared.currentUserID }
  func statistics(poiID: String) async throws -> ReviewStats { try await ReviewsAPI.statistics(poiID: poiID) }
  func placeReviews(poiID: String, page: Int) async throws -> ReviewPage { try await ReviewsAPI.poiReviews(poiID: poiID, page: page) }
  func myReviews(page: Int) async throws -> ReviewPage { try await ReviewsAPI.myReviews(page: page) }

  /// There is no "my review of this POI" RPC, so this reads the caller's
  /// reviews a page of 100 at a time (one page covers nearly everyone).
  func ownReview(poiID: String) async throws -> LociReview? {
    var page = 1
    while page <= 5 {
      let result = try await ReviewsAPI.myReviews(page: page, pageSize: ReviewPayload.ownLookupPageSize)
      if let mine = result.reviews.first(where: { $0.poiID.lowercased() == poiID.lowercased() }) { return mine }
      guard result.hasMore else { return nil }
      page += 1
    }
    return nil
  }

  func create(poiID: String, form: ReviewForm) async throws -> LociReview { try await ReviewsAPI.create(poiID: poiID, form: form) }
  func update(reviewID: String, form: ReviewForm) async throws -> LociReview { try await ReviewsAPI.update(reviewID: reviewID, form: form) }
  func delete(reviewID: String) async throws { try await ReviewsAPI.delete(reviewID: reviewID) }
  func like(reviewID: String, isLike: Bool) async throws -> Int { try await ReviewsAPI.like(reviewID: reviewID, isLike: isLike) }
}
