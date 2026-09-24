import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

/// Reviews (parity pass 2, Phase 5): labels and colour bands (web's
/// ReviewForm/ReviewCard), the form rules, the fold, the helpful vote, the
/// summary maths and the proto mapping.
struct ReviewModelTests {
  @Test func labelsMatchWeb() {
    #expect((1...5).map(ReviewRating.label) == ["Terrible", "Poor", "Average", "Good", "Excellent"])
    #expect(ReviewRating.label(0).isEmpty)
    #expect(ReviewRating.label(6).isEmpty)
  }

  @Test func toneThresholdsAreFourAndThree() {
    #expect(ReviewRating.tone(5) == .high)
    #expect(ReviewRating.tone(4) == .high)
    #expect(ReviewRating.tone(3.9) == .middle)
    #expect(ReviewRating.tone(3) == .middle)
    #expect(ReviewRating.tone(2.9) == .low)
    #expect(ReviewRating.tone(1) == .low)
  }

  @Test func serverRatingsClampToWholeStars() {
    #expect(ReviewRating.clamp(4) == 4)
    #expect(ReviewRating.clamp(0) == 1)
    #expect(ReviewRating.clamp(9) == 5)
    #expect(ReviewRating.clamp(.nan) == 1)
  }

  @Test func formNeedsRatingAndTenCharacters() {
    #expect(ReviewForm().issues == [.noRating, .noContent])
    #expect(ReviewForm(rating: 4, content: "   ").issues == [.noContent])
    // Counted after trimming: nine characters plus padding is still short.
    #expect(ReviewForm(rating: 4, content: "  123456789  ").issues == [.contentTooShort])
    #expect(ReviewForm(rating: 4, content: "1234567890").isValid)
    #expect(ReviewForm(rating: 0, content: "1234567890").issues == [.noRating])
  }

  @Test func formEnforcesTheLimits() {
    let long = String(repeating: "a", count: 1001)
    #expect(ReviewForm(rating: 5, content: long).issues == [.contentTooLong])
    #expect(ReviewForm(rating: 5, content: String(repeating: "a", count: 1000)).isValid)
    #expect(ReviewForm(rating: 5, title: String(repeating: "t", count: 101), content: "long enough").issues == [.titleTooLong])
    #expect(ReviewForm.clampContent(long).count == 1000)
    #expect(ReviewForm.clampTitle(String(repeating: "t", count: 150)).count == 100)
    #expect(ReviewForm(rating: 5, content: "  hello world  ").contentCounter == "11/1000")
    #expect(ReviewForm.Issue.contentTooShort.message == "Review must be at least 10 characters")
  }

  @Test func formStartsFromAReviewForEditing() {
    let visit = Date(timeIntervalSince1970: 1_700_000_000)
    let review = LociReview(id: "r", userID: "u", poiID: LociReview.previewPOI, rating: 3, title: "T", content: "Content here", visitDate: visit)
    #expect(ReviewForm(review) == ReviewForm(rating: 3, title: "T", content: "Content here", visitDate: visit))
  }

  @Test func foldsAfterTwoHundredCharacters() {
    let exact = String(repeating: "x", count: 200)
    #expect(!ReviewText.needsFold(exact))
    #expect(ReviewText.folded(exact) == exact)
    let longer = String(repeating: "y", count: 199) + " and more"
    #expect(ReviewText.needsFold(longer))
    let folded = ReviewText.folded(longer)
    #expect(folded.hasSuffix("\u{2026}"))
    #expect(folded == String(repeating: "y", count: 199) + "\u{2026}")
  }

  @Test func helpfulVoteToggles() {
    let start = HelpfulVote(count: 3)
    #expect(start.tapSendsLike)
    let liked = start.toggled()
    #expect(liked == HelpfulVote(isLiked: true, count: 4))
    #expect(!liked.tapSendsLike)
    let unliked = liked.toggled()
    #expect(unliked == HelpfulVote(isLiked: false, count: 3))
    #expect(HelpfulVote(isLiked: true, count: 0).toggled() == HelpfulVote(count: 0))
    #expect(liked.settled(serverCount: 9) == HelpfulVote(isLiked: true, count: 9))
  }

  @Test func statsShareAndText() {
    let stats = ReviewStats(total: 4, average: 3.75, distribution: [0, 0, 1, 2, 1])
    #expect(stats.share(stars: 4) == 0.5)
    #expect(stats.share(stars: 1) == 0)
    #expect(stats.count(stars: 6) == 0)
    // Locale-formatted, like the stat tiles (the simulator may use a comma).
    #expect(stats.averageText == 3.8.formatted(.number.precision(.fractionLength(1))))
    #expect(stats.countText == "4 reviews")
    #expect(ReviewStats(total: 1, average: 5, distribution: [0, 0, 0, 0, 1]).countText == "1 review")
    #expect(ReviewStats.empty.share(stars: 5) == 0)
  }

  @Test func statsFollowYourOwnWrites() {
    let stats = ReviewStats(total: 2, average: 4, distribution: [0, 0, 1, 0, 1])
    let added = stats.adding(1)
    #expect(added.total == 3)
    #expect(added.average == 3)
    #expect(added.distribution == [1, 0, 1, 0, 1])
    let edited = added.replacing(1, with: 5)
    #expect(edited.distribution == [0, 0, 1, 0, 2])
    #expect(abs(edited.average - 13.0 / 3.0) < 0.0001)
    let removed = ReviewStats(total: 1, average: 5, distribution: [0, 0, 0, 0, 1]).removing(5)
    #expect(removed == ReviewStats.empty)
  }

  @Test func mapsTheProto() {
    var proto = Loci_Review_Review()
    proto.id = "r1"
    proto.userID = "u1"
    proto.contentID = LociReview.previewPOI
    proto.contentName = "Miradouro"
    proto.rating = 4
    proto.content = "Great"
    proto.helpfulCount = 7
    proto.createdAt = Google_Protobuf_Timestamp(date: Date(timeIntervalSince1970: 1000))
    proto.updatedAt = Google_Protobuf_Timestamp(date: Date(timeIntervalSince1970: 4600))
    proto.reviewer.displayName = "  "
    let review = LociReview(proto)
    #expect(review.poiID == LociReview.previewPOI)
    #expect(review.placeName == "Miradouro")
    #expect(review.rating == 4)
    #expect(review.helpfulCount == 7)
    #expect(review.visitDate == nil)
    #expect(review.displayName == "Traveller")
    #expect(review.initial == "T")
    #expect(review.isEdited)
  }

  @Test func mapsStatisticsAndPages() {
    var stats = Loci_Review_ReviewStatistics()
    stats.totalReviews = 3
    stats.overallRating = 4.333
    stats.ratingBreakdown.fourStar = 2
    stats.ratingBreakdown.fiveStar = 1
    let mapped = ReviewStats(stats)
    #expect(mapped.total == 3)
    #expect(mapped.distribution == [0, 0, 0, 2, 1])

    var meta = Loci_Common_PaginationMetadata()
    meta.totalRecords = 41
    meta.hasMore_p = true
    let page = ReviewPage(reviews: [Loci_Review_Review()], pagination: meta)
    #expect(page.total == 41)
    #expect(page.hasMore)
    #expect(ReviewPage(reviews: [], pagination: nil) == ReviewPage(reviews: [], total: 0, hasMore: false))
  }
}

/// The request each ReviewService RPC gets.
struct ReviewPayloadTests {
  private let poiID = LociReview.previewPOI
  private let valid = ReviewForm(rating: 4, title: "  Worth it  ", content: "  Ten or more characters  ")

  @Test func onlyStoredPlacesCanBeReviewed() {
    var stop = Loci_Poi_POIDetailedInfo()
    stop.id = poiID
    #expect(ReviewPayload.canReview(stop))
    stop.id = "Miradouro da Graça"
    #expect(!ReviewPayload.canReview(stop))
    stop.id = "00000000-0000-0000-0000-000000000000"
    #expect(!ReviewPayload.canReview(stop))
  }

  @Test func createSendsTrimmedWholeStarsAndNoUserID() throws {
    let request = try #require(ReviewPayload.create(poiID: poiID, form: valid))
    #expect(request.poiID == poiID)
    #expect(request.rating == 4)
    #expect(request.title == "Worth it")
    #expect(request.content == "Ten or more characters")
    #expect(request.userID.isEmpty)
    #expect(!request.hasVisitDate)
    #expect(request.photoUrls.isEmpty)
    #expect(!request.hasAspects)
  }

  @Test func createRefusesBadInput() {
    #expect(ReviewPayload.create(poiID: "a name", form: valid) == nil)
    #expect(ReviewPayload.create(poiID: poiID, form: ReviewForm(rating: 4, content: "short")) == nil)
    #expect(ReviewPayload.create(poiID: poiID, form: ReviewForm(content: "long enough text")) == nil)
  }

  @Test func visitDateIsTheLocalDayAtNoonUTC() throws {
    var local = Calendar(identifier: .gregorian)
    local.timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
    // 23:30 on 3 March in Auckland is still 3 March to the user.
    let picked = try #require(local.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 23, minute: 30)))
    var form = valid
    form.visitDate = picked
    let request = try #require(ReviewPayload.create(poiID: poiID, form: form, calendar: local))
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    let sent = utc.dateComponents([.year, .month, .day, .hour], from: request.visitDate.date)
    #expect(sent == DateComponents(year: 2026, month: 3, day: 3, hour: 12))
    #expect(ReviewPayload.visitLabel(request.visitDate.date) == "Visited March 2026")
  }

  @Test func updateReplacesEveryField() throws {
    let request = try #require(ReviewPayload.update(reviewID: "r1", form: ReviewForm(rating: 2, content: "Changed my mind")))
    #expect(request.reviewID == "r1")
    #expect(request.rating == 2)
    // No title and no visit date clear them on the server.
    #expect(request.title.isEmpty)
    #expect(!request.hasVisitDate)
    #expect(request.userID.isEmpty)
    #expect(ReviewPayload.update(reviewID: "", form: valid) == nil)
  }

  @Test func likeSendsTheToggleDirection() {
    #expect(ReviewPayload.like(reviewID: "r1", isLike: true).isLike)
    let unlike = ReviewPayload.like(reviewID: "r1", isLike: false)
    #expect(!unlike.isLike)
    #expect(unlike.reviewID == "r1")
    #expect(unlike.userID.isEmpty)
  }

  @Test func listRequestsPageFromOne() {
    let poi = ReviewPayload.poiReviews(poiID: poiID, page: 0)
    #expect(poi.poiID == poiID)
    #expect(poi.pagination.page == 1)
    #expect(poi.pagination.pageSize == 20)
    let mine = ReviewPayload.userReviews(page: 3, pageSize: 500)
    #expect(mine.userID.isEmpty)
    #expect(mine.pagination.page == 3)
    #expect(mine.pagination.pageSize == 100)
    #expect(ReviewPayload.statistics(poiID: poiID).poiID == poiID)
    #expect(ReviewPayload.delete(reviewID: "r9").reviewID == "r9")
  }
}

/// The place store: optimistic votes with rollback, "Edit your review", and a
/// second create switching to edit.
@MainActor struct PlaceReviewsStoreTests {
  private func store(_ service: PreviewReviewsService = PreviewReviewsService()) -> PlaceReviewsStore {
    PlaceReviewsStore(poiID: LociReview.previewPOI, placeName: "Miradouro", service: service)
  }

  @Test func loadsSummaryReviewsAndNoOwnReview() async {
    let store = store()
    await store.load()
    #expect(store.phase == .loaded)
    #expect(store.stats.total == 23)
    #expect(store.latest.count == 3)
    #expect(store.mine == nil)
    #expect(store.showsSeeAll)
  }

  @Test func findsYourOwnReview() async throws {
    let store = store(PreviewReviewsService(ownsPlaceReview: true))
    await store.load()
    let mine = try #require(store.mine)
    #expect(store.isOwn(mine))
    #expect(!store.isOwn(store.reviews[0]))
  }

  @Test func helpfulVoteSettlesOnTheServerCount() async {
    let store = store()
    await store.load()
    let review = store.reviews[0]
    await store.toggleHelpful(review)
    #expect(store.vote(for: review) == HelpfulVote(isLiked: true, count: review.helpfulCount + 1))
    await store.toggleHelpful(review)
    #expect(store.vote(for: review) == HelpfulVote(isLiked: false, count: review.helpfulCount))
  }

  @Test func failedVoteRollsBack() async {
    let store = store(PreviewReviewsService(failLikes: true))
    await store.load()
    let review = store.reviews[1]
    await store.toggleHelpful(review)
    #expect(store.vote(for: review) == HelpfulVote(count: review.helpfulCount))
    #expect(store.error != nil)
  }

  @Test func yourOwnReviewCannotBeVoted() async throws {
    let store = store(PreviewReviewsService(ownsPlaceReview: true))
    await store.load()
    let mine = try #require(store.mine)
    await store.toggleHelpful(mine)
    #expect(store.votes[mine.id] == nil)
  }

  @Test func postingAddsToTheSummary() async {
    let store = store()
    await store.load()
    let result = await store.submit(ReviewForm(rating: 1, content: "Not for me at all"), editing: nil)
    guard case .saved(let saved) = result else {
      Issue.record("expected saved, got \(result)")
      return
    }
    #expect(store.mine == saved)
    #expect(store.reviews.first == saved)
    #expect(store.stats.total == 24)
    #expect(store.stats.count(stars: 1) == 2)
  }

  @Test func secondReviewSwitchesToEdit() async {
    let existing = LociReview.previewMine(poiID: LociReview.previewPOI)
    let store = store(PreviewReviewsService(existingOwn: existing))
    await store.load()
    let result = await store.submit(ReviewForm(rating: 5, content: "Second thoughts, even better"), editing: nil)
    #expect(result == .switchedToEdit(existing))
    #expect(store.mine == existing)
    #expect(store.error == nil)
  }

  @Test func deletingYourReviewTakesItsStar() async throws {
    let store = store(PreviewReviewsService(ownsPlaceReview: true))
    await store.load()
    let mine = try #require(store.mine)
    #expect(await store.delete(mine))
    #expect(store.mine == nil)
    #expect(!store.reviews.contains(mine))
    #expect(store.stats.count(stars: 4) == 5)
  }
}
