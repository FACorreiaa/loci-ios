import Foundation
import LociConnectProto
import Testing

@testable import loci

/// My reviews' summary from GetUserReviews.statistics (proto v5.29.0), with
/// the loaded rows' maths only as the fallback.
struct MyReviewsStatisticsTests {
  private let en = Locale(identifier: "en_US")

  private func review(_ id: String, poi: String, rating: Int = 4, helpful: Int = 0) -> LociReview {
    ReviewsV529Tests.review(id, poi: poi, rating: rating, helpful: helpful)
  }

  // MARK: - My reviews statistics

  @Test func serverStatisticsMapCountAverageAndDistribution() {
    var stats = Loci_Review_UserReviewStatistics()
    stats.totalReviews = 6
    stats.averageRatingGiven = 4.2
    stats.helpfulVotesReceived = 3
    stats.ratingDistribution.fiveStar = 3
    stats.ratingDistribution.fourStar = 2
    stats.ratingDistribution.twoStar = 1
    let summary = ReviewerSummary(stats)
    #expect(summary.total == 6)
    #expect(summary.distribution == [0, 1, 0, 2, 3])
    #expect(summary.hasDistribution)
    #expect(summary.stats.count(stars: 5) == 3)
    #expect(summary.stats.share(stars: 4) == 2.0 / 6.0)
    #expect(summary.text(locale: en) == "6 reviews · 4.2 average · 3 helpful votes")
  }

  @Test func rowFallbackOnlyWhenTheServerSendsNothing() {
    let rows = [review("a", poi: "p", rating: 5, helpful: 2), review("b", poi: "q", rating: 3)]
    let fallback = ReviewerSummary.fromRows(rows, total: 9)
    #expect(fallback?.total == 9, "the server's row count covers every page")
    #expect(fallback?.averageGiven == 4)
    #expect(fallback?.helpfulReceived == 2)
    #expect(fallback?.distribution == [0, 0, 1, 0, 1])
    #expect(ReviewerSummary.fromRows([]) == nil)
  }

  @MainActor @Test func myReviewsPrefersTheServersSummary() async {
    let server = ReviewerSummary(total: 40, averageGiven: 3.9, helpfulReceived: 11, level: "guide", distribution: [1, 2, 5, 12, 20])
    let withStats = MyReviewsStore(service: VoteRecordingService(reviews: [review("a", poi: "p", rating: 5)], summary: server))
    await withStats.load()
    #expect(withStats.summaryStats == server, "one loaded row does not override the server's forty")

    let without = MyReviewsStore(service: VoteRecordingService(reviews: [review("a", poi: "p", rating: 5)]))
    await without.load()
    #expect(without.summaryStats?.total == 1)
    #expect(without.summaryStats?.distribution == [0, 0, 0, 0, 1])
  }
}
