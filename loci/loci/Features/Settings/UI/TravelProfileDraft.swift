import Foundation
import LociConnectProto

/// Form state for one travel profile, with the web form's defaults
/// (TravelProfiles.tsx) and its option lists, so the server sees the same
/// strings from either client.
struct TravelProfileDraft: Identifiable, Equatable {
  // MARK: Option lists (web: TravelProfiles.tsx)
  static let accommodationTypes = ["hotel", "hostel", "apartment", "guesthouse", "resort", "boutique"]
  static let amenities = ["wifi", "parking", "pool", "gym", "spa", "breakfast", "pet_friendly", "business_center", "concierge"]
  static let cuisines = ["italian", "asian", "mediterranean", "mexican", "indian", "french", "american", "local_specialty"]
  static let serviceStyles = ["fine_dining", "casual", "fast_casual", "street_food", "buffet", "takeaway"]
  static let chainVsLocal = ["any", "local_only", "chains_ok", "chains_preferred"]
  static let activityCategories = ["museums", "nightlife", "shopping", "nature", "sports", "arts", "history", "food_tours", "adventure"]
  static let physicalLevels = ["low", "moderate", "high", "extreme"]
  static let indoorOutdoor = ["indoor", "outdoor", "mixed", "weather_dependent"]
  static let planningStyles = ["structured", "flexible", "spontaneous"]
  static let timeFlexibility = ["strict_schedule", "loose_schedule", "completely_flexible"]
  static let seasons = ["spring", "summer", "fall", "winter"]

  var id: String?

  // Basics
  var name = ""
  var isDefault = false
  var searchRadiusKm = 5.0
  var budgetLevel = 2
  var preferredTime = Loci_Profile_DayPreference.any
  var preferredPace = Loci_Profile_SearchPace.moderate
  var preferredTransport = Loci_Profile_TransportPreference.any
  var preferAccessible = false
  var preferOutdoorSeating = false
  var preferDogFriendly = false
  var preferredVibes: [String] = []
  var dietaryNeeds: [String] = []
  var tagIDs: Set<String> = []
  var interestIDs: Set<String> = []

  // Hotels
  var accommodationTypes: Set<String> = []
  var starMin = 1.0
  var starMax = 5.0
  var pricePerNightMin = 0.0
  var pricePerNightMax = 500.0
  var amenities: Set<String> = []

  // Dining
  var cuisines: Set<String> = []
  var serviceStyles: Set<String> = []
  var pricePerPersonMin = 0.0
  var pricePerPersonMax = 200.0
  var chainVsLocal = "any"
  var michelinRated = false
  var localRecommendations = true
  var organic = false

  // Activities
  var activityCategories: Set<String> = []
  var physicalLevel = "moderate"
  var indoorOutdoor = "mixed"
  var educational = false
  var photography = false
  var avoidCrowds = false

  // Planning
  var planningStyle = "flexible"
  var timeFlexibility = "loose_schedule"
  var seasons: Set<String> = ["spring", "summer"]
  var avoidPeakSeason = false

  // Kept from the server so an update does not blank what the form doesn't show.
  private var accommodationExtras = Loci_Profile_AccommodationPreferences()
  private var diningExtras = Loci_Profile_DiningPreferences()
  private var activityExtras = Loci_Profile_ActivityPreferences()
  private var itineraryExtras = Loci_Profile_ItineraryPreferences()

  init(isDefault: Bool = false) { self.isDefault = isDefault }

  init(_ profile: Loci_Profile_UserPreferenceProfile) {
    id = profile.id
    name = profile.profileName
    isDefault = profile.isDefault
    searchRadiusKm = profile.searchRadiusKm > 0 ? profile.searchRadiusKm : 5
    budgetLevel = profile.budgetLevel > 0 ? Int(profile.budgetLevel) : 2
    preferredTime = profile.preferredTime == .unspecified ? .any : profile.preferredTime
    preferredPace = profile.preferredPace == .unspecified ? .any : profile.preferredPace
    preferredTransport = profile.preferredTransport == .unspecified ? .any : profile.preferredTransport
    preferAccessible = profile.preferAccessiblePois
    preferOutdoorSeating = profile.preferOutdoorSeating
    preferDogFriendly = profile.preferDogFriendly
    preferredVibes = profile.preferredVibes
    dietaryNeeds = profile.dietaryNeeds
    tagIDs = Set(profile.tags.map(\.id))
    interestIDs = Set(profile.interests.map(\.id))

    if profile.hasAccommodationPreferences {
      let hotel = profile.accommodationPreferences
      accommodationExtras = hotel
      accommodationTypes = Set(hotel.accommodationType)
      amenities = Set(hotel.amenities)
      if hotel.starRating.hasMin { starMin = hotel.starRating.min }
      if hotel.starRating.hasMax { starMax = hotel.starRating.max }
      if hotel.priceRangePerNight.hasMin { pricePerNightMin = hotel.priceRangePerNight.min }
      if hotel.priceRangePerNight.hasMax { pricePerNightMax = hotel.priceRangePerNight.max }
    }
    if profile.hasDiningPreferences {
      let dining = profile.diningPreferences
      diningExtras = dining
      cuisines = Set(dining.cuisineTypes)
      serviceStyles = Set(dining.serviceStyle)
      if dining.priceRangePerPerson.hasMin { pricePerPersonMin = dining.priceRangePerPerson.min }
      if dining.priceRangePerPerson.hasMax { pricePerPersonMax = dining.priceRangePerPerson.max }
      if dining.hasChainVsLocal { chainVsLocal = dining.chainVsLocal }
      michelinRated = dining.michelinRated
      localRecommendations = dining.localRecommendations
      organic = dining.organicPreference
    }
    if profile.hasActivityPreferences {
      let activity = profile.activityPreferences
      activityExtras = activity
      activityCategories = Set(activity.activityCategories)
      if activity.hasPhysicalActivityLevel { physicalLevel = activity.physicalActivityLevel }
      if activity.hasIndoorOutdoorPreference { indoorOutdoor = activity.indoorOutdoorPreference }
      educational = activity.educationalPreference
      photography = activity.photographyOpportunities
      avoidCrowds = activity.avoidCrowds
    }
    if profile.hasItineraryPreferences {
      let plan = profile.itineraryPreferences
      itineraryExtras = plan
      if plan.hasPlanningStyle { planningStyle = plan.planningStyle }
      if plan.hasTimeFlexibility { timeFlexibility = plan.timeFlexibility }
      seasons = Set(plan.preferredSeasons)
      avoidPeakSeason = plan.avoidPeakSeason
    }
  }

  // MARK: - Requests

  func createRequest() -> Loci_Profile_CreateUserPreferenceProfileRequest {
    var request = Loci_Profile_CreateUserPreferenceProfileRequest()
    request.profileName = name.trimmingCharacters(in: .whitespaces).isEmpty ? "New Profile" : name
    request.isDefault = isDefault
    request.searchRadiusKm = searchRadiusKm
    request.budgetLevel = Int32(budgetLevel)
    request.preferredTime = preferredTime
    request.preferredPace = preferredPace
    request.preferredTransport = preferredTransport
    request.preferAccessiblePois = preferAccessible
    request.preferOutdoorSeating = preferOutdoorSeating
    request.preferDogFriendly = preferDogFriendly
    request.preferredVibes = preferredVibes
    request.dietaryNeeds = dietaryNeeds
    request.tagIds = tagIDs.sorted()
    request.interestIds = interestIDs.sorted()
    request.accommodationPreferences = accommodation
    request.diningPreferences = dining
    request.activityPreferences = activity
    request.itineraryPreferences = itinerary
    return request
  }

  /// The server replaces list fields on update, so every list goes out in full
  /// (the same as web's update mutation).
  func updateRequest(id: String) -> Loci_Profile_UpdateUserPreferenceProfileRequest {
    var request = Loci_Profile_UpdateUserPreferenceProfileRequest()
    request.profileID = id
    if !name.trimmingCharacters(in: .whitespaces).isEmpty { request.profileName = name }
    request.isDefault = isDefault
    request.searchRadiusKm = searchRadiusKm
    request.budgetLevel = Int32(budgetLevel)
    request.preferredTime = preferredTime
    request.preferredPace = preferredPace
    request.preferredTransport = preferredTransport
    request.preferAccessiblePois = preferAccessible
    request.preferOutdoorSeating = preferOutdoorSeating
    request.preferDogFriendly = preferDogFriendly
    request.preferredVibes = preferredVibes
    request.dietaryNeeds = dietaryNeeds
    request.tagIds = tagIDs.sorted()
    request.interestIds = interestIDs.sorted()
    request.accommodationPreferences = accommodation
    request.diningPreferences = dining
    request.activityPreferences = activity
    request.itineraryPreferences = itinerary
    return request
  }

  private static func range(_ min: Double, _ max: Double) -> Loci_Common_RangeFilter {
    var range = Loci_Common_RangeFilter()
    range.min = min
    range.max = max
    return range
  }

  private var accommodation: Loci_Profile_AccommodationPreferences {
    var hotel = accommodationExtras
    hotel.accommodationType = accommodationTypes.sorted()
    hotel.starRating = Self.range(starMin, starMax)
    hotel.priceRangePerNight = Self.range(pricePerNightMin, pricePerNightMax)
    hotel.amenities = amenities.sorted()
    if !hotel.hasChainPreference { hotel.chainPreference = "any" }
    if !hotel.hasBookingFlexibility { hotel.bookingFlexibility = "any" }
    return hotel
  }

  private var dining: Loci_Profile_DiningPreferences {
    var dining = diningExtras
    dining.cuisineTypes = cuisines.sorted()
    dining.serviceStyle = serviceStyles.sorted()
    dining.priceRangePerPerson = Self.range(pricePerPersonMin, pricePerPersonMax)
    dining.chainVsLocal = chainVsLocal
    dining.michelinRated = michelinRated
    dining.localRecommendations = localRecommendations
    dining.organicPreference = organic
    return dining
  }

  private var activity: Loci_Profile_ActivityPreferences {
    var activity = activityExtras
    activity.activityCategories = activityCategories.sorted()
    activity.physicalActivityLevel = physicalLevel
    activity.indoorOutdoorPreference = indoorOutdoor
    if !activity.hasCulturalImmersionLevel { activity.culturalImmersionLevel = "moderate" }
    if !activity.hasMustSeeVsHiddenGems { activity.mustSeeVsHiddenGems = "mixed" }
    if activity.seasonSpecificActivities.isEmpty { activity.seasonSpecificActivities = ["year_round"] }
    activity.educationalPreference = educational
    activity.photographyOpportunities = photography
    activity.avoidCrowds = avoidCrowds
    return activity
  }

  private var itinerary: Loci_Profile_ItineraryPreferences {
    var plan = itineraryExtras
    plan.planningStyle = planningStyle
    plan.timeFlexibility = timeFlexibility
    plan.preferredSeasons = Self.seasons.filter(seasons.contains)
    plan.avoidPeakSeason = avoidPeakSeason
    if !plan.hasPreferredPace { plan.preferredPace = "moderate" }
    if !plan.hasMorningVsEvening { plan.morningVsEvening = "flexible" }
    if !plan.hasWeekendVsWeekday { plan.weekendVsWeekday = "any" }
    if !plan.hasAdventureVsRelaxation { plan.adventureVsRelaxation = "balanced" }
    if !plan.hasSpontaneousVsPlanned { plan.spontaneousVsPlanned = "semi_planned" }
    return plan
  }
}

extension String {
  /// `local_specialty` → `Local specialty`, for chips built from server strings.
  var optionLabel: String {
    let spaced = replacingOccurrences(of: "_", with: " ")
    return spaced.prefix(1).uppercased() + spaced.dropFirst()
  }
}
