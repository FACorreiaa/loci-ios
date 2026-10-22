import Foundation
import LociConnectProto
import Testing

@testable import loci

struct SocialModelTests {
  @Test(arguments: [
    (0, Relationship.unknown),
    (1, .notConnected),
    (2, .requested),
    (3, .incoming),
    (4, .friends),
    (5, .blocked),
    (6, .isSelf),
  ])
  func relationshipFollowsTheProtoNumbers(_ raw: Int, _ expected: Relationship) throws {
    let proto = try #require(Loci_Social_Relationship(rawValue: raw))
    #expect(Relationship(proto) == expected)
  }

  @Test func visibilityRoundTripsAndDefaultsToPrivate() {
    for level in TripVisibility.allCases {
      #expect(TripVisibility(level.proto) == level)
    }
    #expect(TripVisibility(.unspecified) == .onlyMe)
    #expect(!TripVisibility.onlyMe.hasLink)
    #expect(TripVisibility.link.hasLink)
  }

  @Test func initialsUseFirstAndLastName() {
    var user = Loci_Social_PublicUser()
    user.displayName = "Ana Maria Sousa"
    #expect(user.initials == "AS")
    user.displayName = ""
    user.username = "rui"
    #expect(user.initials == "R")
    #expect(user.shownName == "rui")
  }

  @Test(arguments: [
    ("+351 912 345 678", "PT", "+351912345678"),
    ("912 345 678", "PT", "+351912345678"),
    ("00351912345678", "US", "+351912345678"),
    ("07700 900123", "GB", "+447700900123"),
    ("(415) 555-0100", "US", "+14155550100"),
    ("030 1234567", "DE", "+49301234567"),
  ])
  func phonesBecomeE164(_ raw: String, _ region: String, _ expected: String) {
    #expect(ContactHasher.e164(raw, region: region) == expected)
  }

  @Test func unplaceablePhonesAreDropped() {
    #expect(ContactHasher.e164("912 345 678", region: nil) == nil)
    #expect(ContactHasher.e164("912 345 678", region: "ZZ") == nil)
    #expect(ContactHasher.e164("112", region: "PT") == nil)
  }

  @Test func hashesMatchTheServersFormat() {
    // Postgres: encode(sha256(convert_to('+351912345678','UTF8')),'hex')
    #expect(ContactHasher.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    let hashes = ContactHasher.hashes(phones: ["912 345 678", "+351912345678"], emails: [" Ana@Example.COM "], region: "PT")
    #expect(hashes.count == 2)
    #expect(hashes.contains(ContactHasher.sha256Hex("ana@example.com")))
    #expect(hashes.allSatisfy { $0.count == 64 })
  }

  @Test(arguments: [
    (0, FollowState.unknown),
    (1, .notFollowing),
    (2, .requested),
    (3, .following),
    (4, .blocked),
  ])
  func followStateFollowsTheProtoNumbers(_ raw: Int, _ expected: FollowState) throws {
    let proto = try #require(Loci_Social_FollowState(rawValue: raw))
    #expect(FollowState(proto) == expected)
  }

  @Test func ownProfileIsSelfWhateverTheFollowState() throws {
    let relationship = try #require(Loci_Social_Relationship(rawValue: 6))
    #expect(FollowEdge(state: .unspecified, followsYou: false, relationship: relationship).state == .isSelf)
    #expect(FollowEdge(state: .following, followsYou: true).state == .following)
  }

  @Test(arguments: [
    (FollowState.notFollowing, false, "Follow"),
    (.notFollowing, true, "Follow back"),
    (.requested, false, "Requested"),
    (.following, false, "Following"),
    (.following, true, "Friends"),
    (.blocked, false, "Unblock"),
  ])
  func followButtonSaysWhereYouStand(_ state: FollowState, _ followsYou: Bool, _ title: String) {
    let edge = FollowEdge(state: state, followsYou: followsYou)
    #expect(edge.title == title)
    #expect(edge.isFriend == (state == .following && followsYou))
  }

  @Test func feedHeadlinesNameWhatHappened() {
    var item = Loci_Social_FeedItem()
    var summary = Loci_Achievement_AchievementSummary()
    summary.title = "Cartographer"
    summary.kind = .track
    summary.tier = .gold
    item.achievement = summary
    #expect(item.headline == "unlocked Cartographer · Gold")
    #expect(item.detailKind == "achievement")

    var city = Loci_Social_FeedCity()
    city.cityName = "Porto"
    city.country = "Portugal"
    item.city = city
    #expect(item.headline == "explored Porto, Portugal for the first time")

    var trip = Loci_Social_FeedTrip()
    trip.cityName = "Rome"
    item.trip = trip
    item.kind = .tripShared
    #expect(item.headline == "shared a trip: Rome")
    item.kind = .tripFinished
    trip.title = "Three days in Rome"
    item.trip = trip
    #expect(item.headline == "finished a trip: Three days in Rome")
  }

  @Test func cheerLineCountsYouFirst() {
    var item = Loci_Social_FeedItem()
    #expect(item.cheerLine == nil)
    var ana = Loci_Social_PublicUser()
    ana.displayName = "Ana"
    item.cheerCount = 1
    item.recentCheerers = [ana]
    #expect(item.cheerLine == "Ana cheered")
    item.cheerCount = 3
    #expect(item.cheerLine == "Ana and 2 others cheered")
    item.cheeredByMe = true
    #expect(item.cheerLine == "You and 2 others cheered")
    item.cheerCount = 1
    #expect(item.cheerLine == "You cheered")
  }

  @Test func cheeringIsOptimisticAndIdempotent() {
    var item = Loci_Social_FeedItem()
    item.cheerCount = 2
    let cheered = item.cheered(true)
    #expect(cheered.cheeredByMe)
    #expect(cheered.cheerCount == 3)
    #expect(cheered.cheered(true) == cheered)
    #expect(cheered.cheered(false).cheerCount == 2)
    #expect(item.cheered(false) == item)
  }
}
