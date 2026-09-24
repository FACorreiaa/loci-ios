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
