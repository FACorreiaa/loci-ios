import Foundation
import SwiftUI

/// Offline sample data for `-designPreview placeReviews`, `reviewComposer`
/// and `myReviews`, for any place detail shown in a design preview, and for
/// the tests. Writes echo what was sent; `failLikes` makes votes fail and
/// `existingOwn` makes a create hit AlreadyExists, as the server would.
nonisolated struct PreviewReviewsService: ReviewsService {
  static let userID = "0b5e0000-0000-4000-8000-00000000000e"

  var ownsPlaceReview = false
  var failLikes = false
  var existingOwn: LociReview?

  func currentUserID() async -> String? { Self.userID }

  func statistics(poiID: String) async throws -> ReviewStats { ReviewStats(total: 23, average: 4.3, distribution: [1, 1, 2, 6, 13]) }

  func placeReviews(poiID: String, page: Int) async throws -> ReviewPage {
    var reviews = LociReview.previewPlace(poiID: poiID)
    if ownsPlaceReview { reviews.insert(LociReview.previewMine(poiID: poiID), at: 1) }
    return ReviewPage(reviews: page == 1 ? reviews : [], total: 23, hasMore: false)
  }

  func myReviews(page: Int) async throws -> ReviewPage {
    let mine = LociReview.previewMyReviews
    return ReviewPage(reviews: page == 1 ? mine : [], total: mine.count, hasMore: false)
  }

  func ownReview(poiID: String) async throws -> LociReview? {
    if let existingOwn { return existingOwn }
    return ownsPlaceReview ? LociReview.previewMine(poiID: poiID) : nil
  }

  func create(poiID: String, form: ReviewForm) async throws -> LociReview {
    if existingOwn != nil { throw APIError.conflict("review already exists") }
    return LociReview.echo(id: UUID().uuidString, poiID: poiID, form: form)
  }

  func update(reviewID: String, form: ReviewForm) async throws -> LociReview {
    LociReview.echo(id: reviewID, poiID: LociReview.previewPOI, form: form)
  }

  func delete(reviewID: String) async throws {}

  func like(reviewID: String, isLike: Bool) async throws -> Int {
    if failLikes { throw APIError.server("Could not record your vote.") }
    let base = LociReview.previewPlace(poiID: LociReview.previewPOI).first { $0.id == reviewID }?.helpfulCount ?? 0
    return isLike ? base + 1 : base
  }
}

nonisolated extension LociReview {
  /// Miradouro da Senhora do Monte, the Lists previews' first place.
  static let previewPOI = "5c7e0000-0000-4000-8000-000000000001"

  static func echo(id: String, poiID: String, form: ReviewForm) -> LociReview {
    LociReview(
      id: id,
      userID: PreviewReviewsService.userID,
      poiID: poiID,
      rating: form.rating,
      title: form.trimmedTitle,
      content: form.trimmedContent,
      visitDate: form.visitDate,
      createdAt: Date(),
      updatedAt: Date(),
      reviewerName: "You"
    )
  }

  static func previewMine(poiID: String) -> LociReview {
    LociReview(
      id: "7e710000-0000-4000-8000-0000000000aa",
      userID: PreviewReviewsService.userID,
      poiID: poiID,
      placeName: "Miradouro da Senhora do Monte",
      rating: 4,
      title: "Worth the climb",
      content: "Came up at golden hour. Busy, but everyone is there for the same reason and it stays calm. Take the 28 back down.",
      visitDate: day(-40),
      createdAt: day(-38),
      updatedAt: day(-38),
      helpfulCount: 2,
      reviewerName: "Fernando"
    )
  }

  static func previewPlace(poiID: String) -> [LociReview] {
    [
      LociReview(
        id: "7e710000-0000-4000-8000-000000000001",
        userID: "0b5e0000-0000-4000-8000-000000000001",
        poiID: poiID,
        rating: 5,
        title: "The best view in Lisbon, no contest",
        content: "We walked up from Graça around seven and had the whole terrace to ourselves for twenty minutes before the sunset crowd arrived. "
          + "You see the castle, the river and the bridge in one sweep, and the pine trees give a bit of shade in the afternoon. "
          + "Bring water: there is no kiosk at the top, unlike Graça just below.",
        visitDate: day(-12),
        createdAt: day(-10),
        updatedAt: day(-10),
        helpfulCount: 14,
        reviewerName: "Marta Silva",
        isVerified: true
      ),
      LociReview(
        id: "7e710000-0000-4000-8000-000000000002",
        userID: "0b5e0000-0000-4000-8000-000000000002",
        poiID: poiID,
        rating: 3,
        content: "Lovely view, but the tuk-tuks queue right up to the railing after five. Go early.",
        createdAt: day(-21),
        updatedAt: day(-19),
        helpfulCount: 3,
        reviewerName: "Tom"
      ),
      LociReview(
        id: "7e710000-0000-4000-8000-000000000003",
        userID: "0b5e0000-0000-4000-8000-000000000003",
        poiID: poiID,
        rating: 2,
        title: "Overrated at sunset",
        content: "Too crowded to enjoy. Senhora do Monte at 9 am is a different place.",
        createdAt: day(-60),
        updatedAt: day(-60),
        reviewerName: "Aiko"
      ),
    ]
  }

  static var previewMyReviews: [LociReview] {
    [
      previewMine(poiID: previewPOI),
      LociReview(
        id: "7e710000-0000-4000-8000-0000000000ab",
        userID: PreviewReviewsService.userID,
        poiID: "5c7e0000-0000-4000-8000-000000000002",
        placeName: "Taberna da Rua das Flores",
        rating: 5,
        title: "Order what's on the board",
        content: "No bookings, so we queued for half an hour. The pica-pau and the clams were worth every minute.",
        visitDate: day(-90),
        createdAt: day(-88),
        updatedAt: day(-80),
        helpfulCount: 6,
        reviewerName: "Fernando"
      ),
      LociReview(
        id: "7e710000-0000-4000-8000-0000000000ac",
        userID: PreviewReviewsService.userID,
        poiID: "5c7e0000-0000-4000-8000-000000000004",
        placeName: "Feira da Ladra",
        rating: 2,
        content: "Mostly the same stalls as every week now. Fun for an hour if you are nearby on a Saturday.",
        createdAt: day(-140),
        updatedAt: day(-140),
        reviewerName: "Fernando"
      ),
    ]
  }

  private static func day(_ offset: Int) -> Date { Date().addingTimeInterval(Double(offset) * 86_400) }
}

/// `-designPreview placeReviews`: a place's Reviews section on its own.
struct PlaceReviewsPreview: View {
  var body: some View {
    NavigationStack {
      ScrollView {
        PlaceReviewsSection(poiID: LociReview.previewPOI, placeName: "Miradouro da Senhora do Monte", service: PreviewReviewsService())
          .padding(LociTheme.defaultPadding)
      }
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle("Miradouro da Senhora do Monte")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

/// `-designPreview reviewComposer`: editing your own review, over the section.
struct ReviewComposerPreview: View {
  var body: some View {
    PlaceReviewsPreview()
      .sheet(isPresented: .constant(true)) {
        ReviewComposer(mode: .edit(LociReview.previewMine(poiID: LociReview.previewPOI)), placeName: "Miradouro da Senhora do Monte") { form, _ in
          .saved(LociReview.echo(id: "preview", poiID: LociReview.previewPOI, form: form))
        } onDelete: { _ in
          true
        }
      }
  }
}
