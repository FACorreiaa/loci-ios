import Connect
import Foundation
import LociConnectProto
import SwiftProtobuf

/// The ReviewService request builders, kept pure so the fields each RPC gets
/// are tested. `user_id` is never sent: the handler reads the caller from the
/// token, and every request's `user_id` is optional (empty on GetUserReviews
/// means "mine").
nonisolated enum ReviewPayload {
  /// Enough for the place section's three and a first page of "See all".
  static let pageSize: Int32 = 20
  /// GetUserReviews' ceiling (PaginationRequest caps page_size at 100); used
  /// to find the caller's own review of one place.
  static let ownLookupPageSize: Int32 = 100

  /// Reviews hang off a stored POI; a name-keyed stop has none (the same rule
  /// as Add to list: `poi_id` is parsed as a UUID).
  static func canReview(_ stop: Loci_Poi_POIDetailedInfo) -> Bool { canReview(poiID: stop.id) }

  static func canReview(poiID: String) -> Bool { ListPayload.realUUID(poiID) != nil }

  static func statistics(poiID: String) -> Loci_Review_GetReviewStatisticsRequest {
    var request = Loci_Review_GetReviewStatisticsRequest()
    request.poiID = poiID
    return request
  }

  static func poiReviews(poiID: String, page: Int, pageSize: Int32 = pageSize) -> Loci_Review_GetPOIReviewsRequest {
    var request = Loci_Review_GetPOIReviewsRequest()
    request.poiID = poiID
    request.pagination = pagination(page: page, pageSize: pageSize)
    return request
  }

  /// The caller's own reviews: `user_id` left empty on purpose.
  /// web: useMyPOIReview → GetMyPOIReview{poiId}. NotFound when you have none.
  static func myPOIReview(poiID: String) -> Loci_Review_GetMyPOIReviewRequest {
    var request = Loci_Review_GetMyPOIReviewRequest()
    request.poiID = poiID
    return request
  }

  /// How many 100-review pages the fallback lookup reads before giving up.
  static let ownScanMaxPages = 5

  /// What GetMyPOIReview's answer means for "Write" versus "Edit".
  enum OwnLookup: Equatable, Sendable {
    /// The server answered: the review, or none.
    case answered
    /// NotFound: you have not reviewed this place, so the button reads "Write".
    case noReview
    /// Unimplemented: a server older than v5.29.0, so page through your reviews instead.
    case scan
    case failed
  }

  static func ownLookup(_ code: Code?) -> OwnLookup {
    switch code {
    case .none: .answered
    case .some(.notFound): .noReview
    case .some(.unimplemented): .scan
    case .some: .failed
    }
  }

  /// The fallback for servers without GetMyPOIReview (web: fetchMyPOIReview):
  /// your reviews 100 at a time, up to five pages, filtered here by place.
  static func scanForOwn(
    poiID: String,
    maxPages: Int = ownScanMaxPages,
    page fetch: (Int) async throws -> ReviewPage
  ) async throws -> LociReview? {
    let wanted = poiID.lowercased()
    for page in 1...max(1, maxPages) {
      let result = try await fetch(page)
      if let mine = result.reviews.first(where: { $0.poiID.lowercased() == wanted }) { return mine }
      guard result.hasMore, !result.reviews.isEmpty else { return nil }
    }
    return nil
  }

  /// web: useReportReview → ReportReview{reviewId, reason, details}. The
  /// reporter comes from the token, so `user_id` stays empty.
  static func report(reviewID: String, reason: ReviewReport.Reason, details: String = "") -> Loci_Review_ReportReviewRequest {
    var request = Loci_Review_ReportReviewRequest()
    request.reviewID = reviewID
    request.reason = reason.value
    request.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
    return request
  }

  static func userReviews(page: Int, pageSize: Int32 = pageSize) -> Loci_Review_GetUserReviewsRequest {
    var request = Loci_Review_GetUserReviewsRequest()
    request.pagination = pagination(page: page, pageSize: pageSize)
    return request
  }

  /// Nil when the place cannot be reviewed or the form breaks a rule.
  static func create(poiID: String, form: ReviewForm, calendar: Calendar = .current) -> Loci_Review_CreateReviewRequest? {
    guard canReview(poiID: poiID), form.isValid else { return nil }
    var request = Loci_Review_CreateReviewRequest()
    request.poiID = poiID
    request.rating = Double(form.rating)
    request.title = form.trimmedTitle
    request.content = form.trimmedContent
    if let date = form.visitDate { request.visitDate = visitTimestamp(date, calendar: calendar) }
    return request
  }

  /// UpdateReview replaces every editable field, so an empty title or no
  /// visit date clears them (the handler writes what it gets).
  static func update(reviewID: String, form: ReviewForm, calendar: Calendar = .current) -> Loci_Review_UpdateReviewRequest? {
    guard !reviewID.isEmpty, form.isValid else { return nil }
    var request = Loci_Review_UpdateReviewRequest()
    request.reviewID = reviewID
    request.rating = Double(form.rating)
    request.title = form.trimmedTitle
    request.content = form.trimmedContent
    if let date = form.visitDate { request.visitDate = visitTimestamp(date, calendar: calendar) }
    return request
  }

  static func delete(reviewID: String) -> Loci_Review_DeleteReviewRequest {
    var request = Loci_Review_DeleteReviewRequest()
    request.reviewID = reviewID
    return request
  }

  /// `isLike` false takes the caller's vote back (web always sends true).
  static func like(reviewID: String, isLike: Bool) -> Loci_Review_LikeReviewRequest {
    var request = Loci_Review_LikeReviewRequest()
    request.reviewID = reviewID
    request.isLike = isLike
    return request
  }

  /// A visit is a calendar day, not an instant: the local day the picker
  /// shows is sent as noon UTC, so it reads as the same day everywhere.
  static func visitTimestamp(_ date: Date, calendar: Calendar = .current) -> Google_Protobuf_Timestamp {
    Google_Protobuf_Timestamp(date: visitDay(date, calendar: calendar))
  }

  static func visitDay(_ date: Date, calendar: Calendar = .current) -> Date {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12)) ?? date
  }

  /// How a stored visit day reads ("Visited March 2026"), in UTC to match `visitDay`.
  static func visitLabel(_ date: Date) -> String {
    var style = Date.FormatStyle.dateTime.month(.wide).year()
    style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return "Visited \(date.formatted(style))"
  }

  private static func pagination(page: Int, pageSize: Int32) -> Loci_Common_PaginationRequest {
    var pagination = Loci_Common_PaginationRequest()
    pagination.page = Int32(max(1, page))
    pagination.pageSize = min(max(1, pageSize), ownLookupPageSize)
    return pagination
  }
}
