import SwiftUI

/// What the write sheet opens on.
nonisolated enum ReviewComposerMode: Identifiable, Hashable, Sendable {
  case new
  case edit(LociReview)

  var id: String {
    switch self {
    case .new: "new"
    case .edit(let review): review.id
    }
  }

  var review: LociReview? {
    if case .edit(let review) = self { return review }
    return nil
  }
}

/// How a post from the sheet ended.
nonisolated enum ReviewSubmitResult: Equatable, Sendable {
  case saved(LociReview)
  /// The caller had already reviewed the place (AlreadyExists): the sheet
  /// keeps what was typed and saves over that review instead.
  case switchedToEdit(LociReview)
  case failed
}

/// One place's reviews: the summary, the pages loaded so far, the caller's own
/// review and their helpful votes. Shared by the place section and "See all".
@MainActor @Observable final class PlaceReviewsStore {
  enum Phase: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  let poiID: String
  let placeName: String
  private(set) var stats = ReviewStats.empty
  private(set) var reviews: [LociReview] = []
  /// The caller's review of this place, which turns "Write" into "Edit".
  private(set) var mine: LociReview?
  private(set) var userID: String?
  private(set) var phase = Phase.idle
  private(set) var hasMore = false
  private(set) var isLoadingMore = false
  private(set) var votes: [String: HelpfulVote] = [:]
  private var voting: Set<String> = []
  private var page = 1
  var error: String?

  let service: ReviewsService

  init(poiID: String, placeName: String, service: ReviewsService = ConnectReviewsService()) {
    self.poiID = poiID
    self.placeName = placeName
    self.service = service
  }

  var latest: [LociReview] { Array(reviews.prefix(3)) }
  var showsSeeAll: Bool { stats.total > latest.count || hasMore }

  func isOwn(_ review: LociReview) -> Bool {
    guard let userID, !userID.isEmpty else { return false }
    return review.userID.lowercased() == userID.lowercased()
  }

  func vote(for review: LociReview) -> HelpfulVote { votes[review.id] ?? HelpfulVote(count: review.helpfulCount) }

  func load() async {
    if reviews.isEmpty, phase != .loaded { phase = .loading }
    let service = service
    let poiID = poiID
    userID = await service.currentUserID()
    async let stats = service.statistics(poiID: poiID)
    async let first = service.placeReviews(poiID: poiID, page: 1)
    async let own = Self.ownReview(service, poiID: poiID)
    do {
      let (summary, firstPage) = try await (stats, first)
      self.stats = summary
      reviews = firstPage.reviews
      hasMore = firstPage.hasMore
      page = 1
      mine = await own ?? reviews.first(where: isOwn)
      phase = .loaded
    } catch {
      _ = await own
      guard !error.isCancellation else {
        if phase == .loading { phase = .idle }
        return
      }
      if phase == .loaded { self.error = error.userMessage } else { phase = .failed(error.userMessage) }
    }
  }

  func loadMore() async {
    guard hasMore, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let next = try await service.placeReviews(poiID: poiID, page: page + 1)
      let known = Set(reviews.map(\.id))
      reviews += next.reviews.filter { !known.contains($0.id) }
      hasMore = next.hasMore
      page += 1
    } catch { if !error.isCancellation { self.error = error.userMessage } }
  }

  /// Optimistic: the count moves at once, the server's count settles it, and
  /// a refusal puts the vote back. Your own review has no vote button.
  func toggleHelpful(_ review: LociReview) async {
    guard !isOwn(review), !voting.contains(review.id) else { return }
    let before = vote(for: review)
    let after = before.toggled()
    votes[review.id] = after
    voting.insert(review.id)
    defer { voting.remove(review.id) }
    do {
      let count = try await service.like(reviewID: review.id, isLike: after.isLiked)
      votes[review.id] = after.settled(serverCount: count)
    } catch {
      votes[review.id] = before
      if !error.isCancellation { self.error = error.userMessage }
    }
  }

  /// Create, or update `editing`. A second create for the same place is
  /// AlreadyExists; the sheet is then pointed at the existing review.
  func submit(_ form: ReviewForm, editing: LociReview?) async -> ReviewSubmitResult {
    do {
      let saved: LociReview
      if let editing {
        saved = try await service.update(reviewID: editing.id, form: form)
        stats = stats.replacing(editing.rating, with: saved.rating)
        if let index = reviews.firstIndex(where: { $0.id == editing.id }) { reviews[index] = saved } else { reviews.insert(saved, at: 0) }
      } else {
        saved = try await service.create(poiID: poiID, form: form)
        stats = stats.adding(saved.rating)
        reviews.insert(saved, at: 0)
      }
      mine = saved
      phase = .loaded
      Analytics.capture(.reviewSubmitted, ["rating": saved.rating, "is_edit": editing != nil])
      return .saved(saved)
    } catch APIError.conflict(_) where editing == nil {
      if let existing = await Self.ownReview(service, poiID: poiID) {
        mine = existing
        return .switchedToEdit(existing)
      }
      error = "You've already reviewed this place."
      return .failed
    } catch {
      if !error.isCancellation { self.error = error.userMessage }
      return .failed
    }
  }

  /// Optimistic; the review and its star come back if the server refuses.
  func delete(_ review: LociReview) async -> Bool {
    let index = reviews.firstIndex(where: { $0.id == review.id })
    let oldStats = stats
    if let index { reviews.remove(at: index) }
    stats = stats.removing(review.rating)
    if mine?.id == review.id { mine = nil }
    do {
      try await service.delete(reviewID: review.id)
      return true
    } catch {
      if let index { reviews.insert(review, at: min(index, reviews.count)) }
      stats = oldStats
      mine = review
      if !error.isCancellation { self.error = error.userMessage }
      return false
    }
  }

  private nonisolated static func ownReview(_ service: ReviewsService, poiID: String) async -> LociReview? {
    try? await service.ownReview(poiID: poiID)
  }
}

/// Profile › My reviews: the caller's reviews, newest first, with edit and delete.
@MainActor @Observable final class MyReviewsStore {
  enum Phase: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  private(set) var reviews: [LociReview] = []
  private(set) var total = 0
  private(set) var phase = Phase.idle
  private(set) var hasMore = false
  private(set) var isLoadingMore = false
  private var page = 1
  var error: String?

  let service: ReviewsService

  init(service: ReviewsService = ConnectReviewsService()) { self.service = service }

  /// "4.4 average · 12 helpful votes", from what is loaded (the server leaves
  /// GetUserReviews' statistics empty).
  var summary: String {
    guard !reviews.isEmpty else { return "" }
    let average = Double(reviews.map(\.rating).reduce(0, +)) / Double(reviews.count)
    let helpful = reviews.map(\.helpfulCount).reduce(0, +)
    var parts = [total == 1 ? "1 review" : "\(max(total, reviews.count)) reviews"]
    parts.append("\(average.formatted(.number.precision(.fractionLength(1)))) average")
    if helpful > 0 { parts.append(helpful == 1 ? "1 helpful vote" : "\(helpful) helpful votes") }
    return parts.joined(separator: " · ")
  }

  func load() async {
    if reviews.isEmpty { phase = .loading }
    do {
      let first = try await service.myReviews(page: 1)
      reviews = first.reviews
      total = first.total
      hasMore = first.hasMore
      page = 1
      phase = .loaded
    } catch {
      guard !error.isCancellation else {
        if phase == .loading { phase = .idle }
        return
      }
      if reviews.isEmpty { phase = .failed(error.userMessage) } else { self.error = error.userMessage }
    }
  }

  func loadMore() async {
    guard hasMore, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let next = try await service.myReviews(page: page + 1)
      let known = Set(reviews.map(\.id))
      reviews += next.reviews.filter { !known.contains($0.id) }
      hasMore = next.hasMore
      page += 1
    } catch { if !error.isCancellation { self.error = error.userMessage } }
  }

  func update(_ review: LociReview, form: ReviewForm) async -> ReviewSubmitResult {
    do {
      let saved = try await service.update(reviewID: review.id, form: form)
      if let index = reviews.firstIndex(where: { $0.id == review.id }) {
        var merged = saved
        // The update echo may not carry the joined place name.
        if merged.placeName.isEmpty { merged.placeName = review.placeName }
        reviews[index] = merged
      }
      Analytics.capture(.reviewSubmitted, ["rating": saved.rating, "is_edit": true])
      return .saved(saved)
    } catch {
      if !error.isCancellation { self.error = error.userMessage }
      return .failed
    }
  }

  /// Optimistic, with the row put back on failure.
  func delete(_ review: LociReview) async -> Bool {
    guard let index = reviews.firstIndex(of: review) else { return false }
    reviews.remove(at: index)
    total = max(0, total - 1)
    do {
      try await service.delete(reviewID: review.id)
      return true
    } catch {
      reviews.insert(review, at: min(index, reviews.count))
      total += 1
      if !error.isCancellation { self.error = error.userMessage }
      return false
    }
  }
}
