import Foundation
import LociConnectProto
import SwiftProtobuf

/// One review as the screens use it, flattened from `Loci_Review_Review`.
/// Reviews exist only for stored POIs (the server rejects anything else), so
/// `poiID` is always a UUID and `placeName` is the server's `content_name`.
nonisolated struct LociReview: Identifiable, Hashable, Sendable {
  var id: String
  var userID: String
  var poiID: String
  var placeName: String
  /// Whole stars, 1–5 (the server refuses fractions).
  var rating: Int
  var title: String
  var content: String
  var visitDate: Date?
  var createdAt: Date?
  var updatedAt: Date?
  var helpfulCount: Int
  var reviewerName: String
  var reviewerAvatar: URL?
  var isVerified: Bool
  /// Whether the caller has marked this review helpful (server-filled per viewer).
  var votedByMe: Bool

  init(
    id: String,
    userID: String,
    poiID: String,
    placeName: String = "",
    rating: Int,
    title: String = "",
    content: String,
    visitDate: Date? = nil,
    createdAt: Date? = nil,
    updatedAt: Date? = nil,
    helpfulCount: Int = 0,
    reviewerName: String = "",
    reviewerAvatar: URL? = nil,
    isVerified: Bool = false,
    votedByMe: Bool = false
  ) {
    self.id = id
    self.userID = userID
    self.poiID = poiID
    self.placeName = placeName
    self.rating = rating
    self.title = title
    self.content = content
    self.visitDate = visitDate
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.helpfulCount = helpfulCount
    self.reviewerName = reviewerName
    self.reviewerAvatar = reviewerAvatar
    self.isVerified = isVerified
    self.votedByMe = votedByMe
  }

  init(_ review: Loci_Review_Review) {
    let poiID = review.poiID.isEmpty ? review.contentID : review.poiID
    self.init(
      id: review.id,
      userID: review.userID.isEmpty ? review.reviewer.userID : review.userID,
      poiID: poiID,
      placeName: review.contentName,
      rating: ReviewRating.clamp(review.rating),
      title: review.title,
      content: review.content,
      visitDate: review.hasVisitDate ? review.visitDate.date : nil,
      createdAt: review.hasCreatedAt ? review.createdAt.date : nil,
      updatedAt: review.hasUpdatedAt ? review.updatedAt.date : nil,
      helpfulCount: Int(max(0, review.helpfulCount)),
      reviewerName: review.reviewer.displayName,
      reviewerAvatar: review.reviewer.avatarURL.isEmpty ? nil : URL(string: review.reviewer.avatarURL),
      isVerified: review.isVerified || review.reviewer.isVerified,
      votedByMe: review.votedByMe
    )
  }

  /// The server leaves `display_name` empty for accounts without one.
  var displayName: String {
    let name = reviewerName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "Traveller" : name
  }

  /// The avatar fallback: the name's first letter.
  var initial: String { String(displayName.prefix(1)).uppercased() }

  /// Changed after it was first posted (a minute's grace for the insert's own
  /// timestamps, which are two `NOW()`s).
  var isEdited: Bool {
    guard let createdAt, let updatedAt else { return false }
    return updatedAt.timeIntervalSince(createdAt) > 60
  }
}

/// A POI's count, average and star breakdown (GetReviewStatistics). The
/// server computes nothing else: trends, tags and aspects stay empty.
nonisolated struct ReviewStats: Equatable, Sendable {
  var total: Int
  var average: Double
  /// Counts for 1…5 stars, index 0 = one star.
  var distribution: [Int]

  static let empty = ReviewStats(total: 0, average: 0, distribution: [0, 0, 0, 0, 0])

  init(total: Int, average: Double, distribution: [Int]) {
    self.total = max(0, total)
    self.average = min(max(average, 0), 5)
    let padded = (distribution + [0, 0, 0, 0, 0]).prefix(5).map { max(0, $0) }
    self.distribution = Array(padded)
  }

  init(_ stats: Loci_Review_ReviewStatistics) {
    let breakdown = stats.ratingBreakdown
    self.init(
      total: Int(stats.totalReviews),
      average: stats.overallRating,
      distribution: [breakdown.oneStar, breakdown.twoStar, breakdown.threeStar, breakdown.fourStar, breakdown.fiveStar].map(Int.init)
    )
  }

  func count(stars: Int) -> Int {
    guard (1...5).contains(stars) else { return 0 }
    return distribution[stars - 1]
  }

  /// The bar length for a star row, 0…1. The breakdown's own sum is the
  /// denominator so the bars stay consistent even if `total` lags.
  func share(stars: Int) -> Double {
    let sum = distribution.reduce(0, +)
    guard sum > 0 else { return 0 }
    return Double(count(stars: stars)) / Double(sum)
  }

  /// "4.3", one decimal, as the stat tiles show ratings.
  var averageText: String { average.formatted(.number.precision(.fractionLength(1))) }

  var countText: String { total == 1 ? "1 review" : "\(total) reviews" }

  /// After the caller's own write, without waiting for a re-fetch.
  func adding(_ rating: Int) -> ReviewStats { replacing(nil, with: rating) }

  func removing(_ rating: Int) -> ReviewStats { replacing(rating, with: nil) }

  func replacing(_ old: Int?, with new: Int?) -> ReviewStats {
    var counts = distribution
    var sumOfStars = average * Double(total)
    var total = total
    if let old, (1...5).contains(old), counts[old - 1] > 0 {
      counts[old - 1] -= 1
      sumOfStars -= Double(old)
      total -= 1
    }
    if let new, (1...5).contains(new) {
      counts[new - 1] += 1
      sumOfStars += Double(new)
      total += 1
    }
    return ReviewStats(total: total, average: total > 0 ? sumOfStars / Double(total) : 0, distribution: counts)
  }
}

/// One page of reviews and whether there is another.
nonisolated struct ReviewPage: Equatable, Sendable {
  var reviews: [LociReview]
  var total: Int
  var hasMore: Bool
  /// My reviews only: the server's totals for the caller (GetUserReviews.statistics).
  var summary: ReviewerSummary?

  init(reviews: [LociReview], total: Int, hasMore: Bool, summary: ReviewerSummary? = nil) {
    self.reviews = reviews
    self.total = total
    self.hasMore = hasMore
    self.summary = summary
  }

  init(reviews: [Loci_Review_Review], pagination: Loci_Common_PaginationMetadata?, summary: ReviewerSummary? = nil) {
    let mapped = reviews.map(LociReview.init)
    self.init(
      reviews: mapped,
      total: Int(pagination?.totalRecords ?? Int32(mapped.count)),
      hasMore: pagination?.hasMore_p ?? false,
      summary: summary
    )
  }

  init(_ response: Loci_Review_GetUserReviewsResponse) {
    self.init(
      reviews: response.reviews,
      pagination: response.hasPagination ? response.pagination : nil,
      summary: response.hasStatistics ? ReviewerSummary(response.statistics) : nil
    )
  }
}

/// "7 reviews · 4.3 average · 12 helpful votes · Guide": the caller's totals
/// over all their reviews (GetUserReviews.statistics, web: mineSummary), with
/// how many gave each star. Worked out from the loaded rows only when a server
/// leaves the statistics empty (`fromRows`).
nonisolated struct ReviewerSummary: Equatable, Sendable {
  var total: Int
  var averageGiven: Double
  var helpfulReceived: Int
  /// new / explorer / guide / expert at 1 / 5 / 20 reviews; empty on old servers.
  var level: String
  /// Your reviews per star, index 0 = one star.
  var distribution: [Int]

  init(total: Int, averageGiven: Double, helpfulReceived: Int, level: String, distribution: [Int] = [0, 0, 0, 0, 0]) {
    self.total = max(0, total)
    self.averageGiven = min(max(averageGiven, 0), 5)
    self.helpfulReceived = max(0, helpfulReceived)
    self.level = level
    self.distribution = Array((distribution + [0, 0, 0, 0, 0]).prefix(5).map { max(0, $0) })
  }

  init(_ proto: Loci_Review_UserReviewStatistics) {
    let breakdown = proto.ratingDistribution
    self.init(
      total: Int(proto.totalReviews),
      averageGiven: proto.averageRatingGiven,
      helpfulReceived: Int(proto.helpfulVotesReceived),
      level: proto.reviewerLevel,
      distribution: [breakdown.oneStar, breakdown.twoStar, breakdown.threeStar, breakdown.fourStar, breakdown.fiveStar].map(Int.init)
    )
  }

  /// The fallback: the rows loaded so far (web: summariseMine). `total` is the
  /// server's row count when it sent one, so the count covers every page even
  /// though the average and bars cover only what is loaded. Nil with no rows.
  static func fromRows(_ reviews: [LociReview], total: Int = 0) -> ReviewerSummary? {
    guard !reviews.isEmpty else { return nil }
    var counts = [0, 0, 0, 0, 0]
    for review in reviews { counts[ReviewRating.clamp(Double(review.rating)) - 1] += 1 }
    return ReviewerSummary(
      total: max(total, reviews.count),
      averageGiven: Double(reviews.map(\.rating).reduce(0, +)) / Double(reviews.count),
      helpfulReceived: reviews.map(\.helpfulCount).reduce(0, +),
      level: "",
      distribution: counts
    )
  }

  /// The same numbers as a place summary, for the star bars.
  var stats: ReviewStats { ReviewStats(total: total, average: averageGiven, distribution: distribution) }

  var hasDistribution: Bool { distribution.contains { $0 > 0 } }

  var text: String { text() }

  func text(locale: Locale = .current) -> String {
    var parts = [total == 1 ? "1 review" : "\(total) reviews"]
    parts.append("\(averageGiven.formatted(.number.precision(.fractionLength(1)).locale(locale))) average")
    if helpfulReceived > 0 { parts.append(helpfulReceived == 1 ? "1 helpful vote" : "\(helpfulReceived) helpful votes") }
    let level = level.trimmingCharacters(in: .whitespacesAndNewlines)
    if !level.isEmpty { parts.append(level.prefix(1).uppercased() + level.dropFirst()) }
    return parts.joined(separator: " · ")
  }
}
