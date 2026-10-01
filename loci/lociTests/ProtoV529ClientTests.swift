import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

/// Client halves of proto v5.29.0: the server now says whether you voted,
/// answers "my review of this place" directly, takes reports, fills My
/// reviews' statistics, lists your claims, and puts an id and a duration on
/// each globe arc. Each test pins one of those on the model layer.
struct ProtoV529ClientTests {
  private let en = Locale(identifier: "en_US")

  // MARK: - Reviews

  @Test func reviewMapsVotedByMeAndTheVoteStartsFromIt() {
    var proto = Loci_Review_Review()
    proto.id = "r-1"
    proto.userID = "u-2"
    proto.poiID = "p-1"
    proto.rating = 4
    proto.content = "fine"
    proto.helpfulCount = 3
    proto.votedByMe = true
    let review = LociReview(proto)
    #expect(review.votedByMe)
    #expect(HelpfulVote(review) == HelpfulVote(isLiked: true, count: 3))
    proto.votedByMe = false
    #expect(HelpfulVote(LociReview(proto)) == HelpfulVote(isLiked: false, count: 3))
  }

  @Test func myReviewsPageCarriesTheServerSummary() {
    var response = Loci_Review_GetUserReviewsResponse()
    response.statistics.totalReviews = 7
    response.statistics.averageRatingGiven = 4.3
    response.statistics.helpfulVotesReceived = 12
    response.statistics.reviewerLevel = "guide"
    let page = ReviewPage(response)
    #expect(page.summary == ReviewerSummary(total: 7, averageGiven: 4.3, helpfulReceived: 12, level: "guide"))
    #expect(page.summary?.text(locale: en) == "7 reviews · 4.3 average · 12 helpful votes · Guide")
    #expect(ReviewPage(Loci_Review_GetUserReviewsResponse()).summary == nil, "no statistics → no summary")
  }

  @Test func reviewerSummaryWording() {
    #expect(ReviewerSummary(total: 1, averageGiven: 5, helpfulReceived: 0, level: "").text(locale: en) == "1 review · 5.0 average")
    let two = ReviewerSummary(total: 2, averageGiven: 3.5, helpfulReceived: 1, level: "new")
    #expect(two.text(locale: en) == "2 reviews · 3.5 average · 1 helpful vote · New")
  }

  @Test func reportReasonsMatchWebAndTheRequestShape() {
    #expect(ReviewReport.reasons.map(\.value) == ["spam", "inappropriate", "fake", "offensive", "other"])
    let request = ReviewPayload.report(reviewID: "r-1", reason: .fake, details: "  copied from elsewhere ")
    #expect(request.reviewID == "r-1")
    #expect(request.reason == "fake")
    #expect(request.details == "copied from elsewhere")
    #expect(request.userID.isEmpty, "the server takes the reporter from the token")
    #expect(ReviewPayload.myPOIReview(poiID: "p-9").poiID == "p-9")
  }

  // MARK: - Contribute

  @Test func myClaimMapsFieldStatusAndWording() {
    var proto = Loci_Place_MyPlaceClaim()
    proto.claimID = "c-1"
    proto.poiID = "p-1"
    proto.poiName = "Tasca do Chico"
    proto.field = .openingHours
    proto.value = "Mon–Fri 12:00–23:00"
    proto.status = .pending
    proto.createdAt = Google_Protobuf_Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000))
    let claim = MyClaim(proto)
    #expect(claim.id == "c-1")
    #expect(claim.placeName == "Tasca do Chico")
    #expect(claim.fieldLabel == "Opening Hours")
    #expect(claim.value == "Mon–Fri 12:00–23:00")
    #expect(claim.status == .pending)
    #expect(claim.statusText == "Recorded")
    #expect(claim.createdAt == Date(timeIntervalSince1970: 1_700_000_000))

    proto.poiName = ""
    #expect(MyClaim(proto).placeName == "A place since removed")
    #expect(MyClaim.statusText(.accepted) == "Verified")
    #expect(MyClaim.statusText(.contradicted) == "Noted")
    #expect(MyClaim.statusText(.expired) == "Expired")
    #expect(MyClaim.statusText(.unspecified) == "Recorded")
  }

  @Test func myClaimsRequestDefaultsToTwentyOnTheFirstPage() {
    let first = ContributePayload.myClaims()
    #expect(first.limit == 20)
    #expect(first.page == 1)
    let third = ContributePayload.myClaims(page: 3, limit: 150)
    #expect(third.page == 3)
    #expect(third.limit == 100, "the server caps at 100")
  }

  // MARK: - Globe

  @Test func legsUseTheServerIdAndDurationWhenSent() {
    var arc = Loci_Travelhistory_GlobeArc()
    arc.id = "leg-7"
    arc.tripID = "t1"
    arc.fromName = "Lisbon"
    arc.toName = "Porto"
    arc.distanceKm = 274
    arc.durationMins = 185
    let leg = GlobeMapping.legs([arc])[0]
    #expect(leg.id == "leg-7")
    #expect(leg.durationMins == 185)

    arc.id = ""
    arc.durationMins = 0
    let fallback = GlobeMapping.legs([arc])[0]
    #expect(fallback.id == GlobeLegKey.base(tripId: "t1", from: "Lisbon", to: "Porto", occurredAt: nil), "older servers: composite key")
    #expect(fallback.durationMins == nil, "zero means unknown, never 0h 0m")
  }
}
