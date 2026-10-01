import Connect
import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Reviews against proto v5.29.0: "my review of this place" with the old scan
/// as the fallback, report refusals in plain words, votes starting from
/// `voted_by_me`.
struct ReviewsV529Tests {
  static func review(_ id: String, poi: String, rating: Int = 4, helpful: Int = 0, voted: Bool = false) -> LociReview {
    LociReview(
      id: id,
      userID: "u-1",
      poiID: poi,
      placeName: "Place \(id)",
      rating: rating,
      title: "",
      content: "A fine place to sit.",
      helpfulCount: helpful,
      votedByMe: voted
    )
  }

  // MARK: - My review of a place

  @Test func ownLookupReadsTheServersAnswer() {
    #expect(ReviewPayload.ownLookup(nil) == .answered)
    #expect(ReviewPayload.ownLookup(.notFound) == .noReview, "NotFound means write a review")
    #expect(ReviewPayload.ownLookup(.unimplemented) == .scan, "an older server: scan your reviews")
    #expect(ReviewPayload.ownLookup(.internalError) == .failed)
    #expect(ReviewPayload.ownLookup(.unauthenticated) == .failed)
  }

  @Test func myPOIReviewRequestCarriesOnlyThePlace() {
    let request = ReviewPayload.myPOIReview(poiID: "5f0c0000-0000-4000-8000-000000000001")
    #expect(request.poiID == "5f0c0000-0000-4000-8000-000000000001")
  }

  @Test func scanFallbackFindsYourReviewOnALaterPage() async throws {
    let pages: [Int: ReviewPage] = [
      1: ReviewPage(reviews: [Self.review("a", poi: "P-1"), Self.review("b", poi: "p-2")], total: 3, hasMore: true),
      2: ReviewPage(reviews: [Self.review("c", poi: "P-3")], total: 3, hasMore: false),
    ]
    var asked: [Int] = []
    let found = try await ReviewPayload.scanForOwn(poiID: "p-3") { page in
      asked.append(page)
      return pages[page] ?? ReviewPage(reviews: [], total: 0, hasMore: false)
    }
    #expect(found?.id == "c", "matched case-insensitively")
    #expect(asked == [1, 2])
  }

  @Test func scanFallbackStopsAtTheLastPageOrTheCap() async throws {
    var asked: [Int] = []
    let none = try await ReviewPayload.scanForOwn(poiID: "p-9") { page in
      asked.append(page)
      return ReviewPage(reviews: [Self.review("x\(page)", poi: "p-1")], total: 1, hasMore: false)
    }
    #expect(none == nil)
    #expect(asked == [1])

    asked = []
    _ = try await ReviewPayload.scanForOwn(poiID: "p-9", maxPages: 3) { page in
      asked.append(page)
      return ReviewPage(reviews: [Self.review("x\(page)", poi: "p-1")], total: 999, hasMore: true)
    }
    #expect(asked == [1, 2, 3], "never more than the cap")
  }

  // MARK: - Reports

  @Test func reportRefusalsReadAsPlainSentences() {
    #expect(ReviewReport.refusal(.permissionDenied) == "You can't report your own review.")
    #expect(ReviewReport.refusal(.failedPrecondition) == "This review can't be reported right now.")
    #expect(ReviewReport.refusal(nil) == nil)
    #expect(ReviewReport.refusal(.unavailable) == nil, "other failures keep the usual wording")
  }

  @Test func reportRequestForEveryReason() {
    for reason in ReviewReport.reasons {
      let request = ReviewPayload.report(reviewID: "r-1", reason: reason)
      #expect(request.reason == reason.rawValue)
      #expect(request.details.isEmpty)
      #expect(request.userID.isEmpty)
    }
  }

  // MARK: - Votes

  @MainActor @Test func aVoteFromAnEarlierSessionIsTakenBackOnTheFirstTap() async {
    let service = VoteRecordingService(reviews: [Self.review("r-1", poi: "p-1", helpful: 3, voted: true)])
    let store = PlaceReviewsStore(poiID: "p-1", placeName: "Place", service: service)
    await store.load()
    let loaded = store.reviews[0]
    #expect(store.vote(for: loaded) == HelpfulVote(isLiked: true, count: 3))
    await store.toggleHelpful(loaded)
    #expect(service.likes == [false], "the first tap unlikes")
    #expect(store.vote(for: loaded) == HelpfulVote(isLiked: false, count: 2))
  }

  @MainActor @Test func reportingSomeoneElsesReviewMarksItAndYourOwnIsRefused() async {
    let service = VoteRecordingService(reviews: [Self.review("r-1", poi: "p-1"), mineReview()])
    let store = PlaceReviewsStore(poiID: "p-1", placeName: "Place", service: service)
    await store.load()
    #expect(await store.report(store.reviews[0], reason: .spam))
    #expect(store.reported.contains("r-1"))
    #expect(await store.report(store.reviews[1], reason: .spam) == false, "your own review has no report")
    #expect(service.reports == ["r-1:spam"])
  }

  private func mineReview() -> LociReview {
    var own = Self.review("r-me", poi: "p-1")
    own.userID = VoteRecordingService.me
    return own
  }
}

/// Records likes and reports; serves fixed reviews.
final class VoteRecordingService: ReviewsService, @unchecked Sendable {
  static let me = "u-me"
  let reviews: [LociReview]
  let summary: ReviewerSummary?
  private let lock = NSLock()
  private var likeLog: [Bool] = []
  private var reportLog: [String] = []

  init(reviews: [LociReview], summary: ReviewerSummary? = nil) {
    self.reviews = reviews
    self.summary = summary
  }

  var likes: [Bool] { lock.withLock { likeLog } }
  var reports: [String] { lock.withLock { reportLog } }

  func currentUserID() async -> String? { Self.me }
  func statistics(poiID: String) async throws -> ReviewStats { .empty }
  func placeReviews(poiID: String, page: Int) async throws -> ReviewPage { ReviewPage(reviews: reviews, total: reviews.count, hasMore: false) }
  func myReviews(page: Int) async throws -> ReviewPage { ReviewPage(reviews: reviews, total: reviews.count, hasMore: false, summary: summary) }
  func ownReview(poiID: String) async throws -> LociReview? { nil }
  func create(poiID: String, form: ReviewForm) async throws -> LociReview { throw APIError.custom("unused") }
  func update(reviewID: String, form: ReviewForm) async throws -> LociReview { throw APIError.custom("unused") }
  func delete(reviewID: String) async throws {}

  func like(reviewID: String, isLike: Bool) async throws -> Int {
    lock.withLock { likeLog.append(isLike) }
    return reviews.first { $0.id == reviewID }.map { max(0, $0.helpfulCount + (isLike ? 1 : -1)) } ?? 0
  }

  func report(reviewID: String, reason: ReviewReport.Reason) async throws {
    lock.withLock { reportLog.append("\(reviewID):\(reason.rawValue)") }
  }
}
