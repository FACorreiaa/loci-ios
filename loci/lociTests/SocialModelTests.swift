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
}
