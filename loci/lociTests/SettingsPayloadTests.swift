import Foundation
import LociConnectProto
import Testing

@testable import loci

@MainActor struct SettingsPayloadTests {
  @Test func profileUpdateOmitsUnchangedAndEmptyFields() {
    var old = ProfileDraft()
    old.displayName = "Ana"
    old.city = "Lisbon"
    var new = old
    new.displayName = "Ana"
    new.city = "  Porto "
    new.phoneNumber = ""
    new.username = "   "

    let params = new.changes(from: old)

    #expect(!params.hasDisplayName)
    #expect(params.hasCity && params.city == "Porto")
    // optional + min_len:1 on the server: an empty string must never be marked present.
    #expect(!params.hasPhoneNumber)
    #expect(!params.hasUsername)
  }

  @Test func newTravelProfileSendsWebDefaults() {
    let request = TravelProfileDraft(isDefault: true).createRequest()

    #expect(request.profileName == "New Profile")
    #expect(request.isDefault)
    #expect(request.searchRadiusKm == 5)
    #expect(request.budgetLevel == 2)
    #expect(request.preferredPace == .moderate)
    #expect(request.accommodationPreferences.starRating.min == 1)
    #expect(request.accommodationPreferences.priceRangePerNight.max == 500)
    #expect(request.diningPreferences.localRecommendations)
    #expect(request.activityPreferences.seasonSpecificActivities == ["year_round"])
    #expect(request.itineraryPreferences.preferredSeasons == ["spring", "summer"])
    #expect(request.itineraryPreferences.spontaneousVsPlanned == "semi_planned")
  }

  @Test func travelProfileUpdateSendsIdsAndFullLists() {
    var profile = Loci_Profile_UserPreferenceProfile()
    profile.id = "p1"
    profile.profileName = "Weekend"
    var interest = Loci_Interest_Interest()
    interest.id = "i1"
    interest.name = "Museums"
    profile.interests = [interest]
    profile.dietaryNeeds = ["vegan"]

    var draft = TravelProfileDraft(profile)
    draft.cuisines = ["italian"]
    let request = draft.updateRequest(id: "p1")

    #expect(request.profileID == "p1")
    // Ids, not names: names made every create with a selection fail (web: profiles.ts).
    #expect(request.interestIds == ["i1"])
    #expect(request.dietaryNeeds == ["vegan"])
    #expect(request.diningPreferences.cuisineTypes == ["italian"])
  }

  @Test func telegramDeepLinkMatchesWeb() {
    #expect(TelegramSection.deepLink(bot: "@LociBot", code: "AB12")?.absoluteString == "https://t.me/LociBot?start=AB12")
    #expect(TelegramSection.deepLink(bot: "", code: "AB12") == nil)
  }
}
