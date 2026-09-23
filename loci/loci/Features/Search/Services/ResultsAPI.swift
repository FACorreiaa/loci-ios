import Connect
import Foundation
import LociConnectProto
import SwiftProtobuf

/// The RPCs a result page calls beside the stream, with the fields web sends.
nonisolated enum ResultsAPI {
  private static var transport: ProtocolClientInterface { ConnectTransport.shared.protocolClient }
  static let localContext = Loci_Localcontext_LocalContextServiceClient(client: transport)
  static let payment = Loci_Payment_V1_PaymentServiceClient(client: transport)
  static let places = Loci_Place_PlaceIntelligenceServiceClient(client: transport)
  static let favorites = Loci_Favorites_V1_FavoritesServiceClient(client: transport)
  static let export = Loci_Export_ExportServiceClient(client: transport)
  static let itineraries = Loci_Itinerary_ItineraryServiceClient(client: transport)

  /// web: LocalWeather → GetLocalContext{latitude, longitude, days: 5}
  static func localContext(latitude: Double, longitude: Double) async throws -> Loci_Localcontext_LocalContext {
    var request = Loci_Localcontext_GetLocalContextRequest()
    request.latitude = latitude
    request.longitude = longitude
    request.days = 5
    return try await rpc("Could not load the local forecast.", request) { await localContext.getLocalContext(request: $0, headers: [:]) }
  }

  /// web: TripMoney → GetFxRates{latitude, longitude}; the server resolves the country.
  static func fxRates(latitude: Double, longitude: Double) async throws -> Loci_Localcontext_GetFxRatesResponse {
    var request = Loci_Localcontext_GetFxRatesRequest()
    request.latitude = latitude
    request.longitude = longitude
    return try await rpc("Could not load exchange rates.", request) { await localContext.getFxRates(request: $0, headers: [:]) }
  }

  /// web: PaymentService.GetSubscription → plan id (`premium_annual`, `free`, …).
  static func plan() async throws -> String {
    let response = try await rpc("Could not confirm your plan.") { await payment.getSubscription(request: .init(), headers: [:]) }
    return response.hasSubscription ? response.subscription.planID : "free"
  }

  /// web: DetailedItemModal → GetPlaceFacts{poiId}
  static func placeFacts(poiID: String) async throws -> Loci_Place_PlaceFacts {
    var request = Loci_Place_GetPlaceFactsRequest()
    request.poiID = poiID
    return try await rpc("Could not load verified facts.", request) { await places.getPlaceFacts(request: $0, headers: [:]) }
  }

  /// web: FavoriteButton → AddToFavorites. Real id, city name and the domain's
  /// content type, which is what makes the saved place open again later.
  static func addFavorite(_ poi: Loci_Poi_POIDetailedInfo, destination: SearchDestination, cityName: String) async throws {
    var request = Loci_Favorites_V1_AddToFavoritesRequest()
    request.userID = await AuthSessionManager.shared.currentUserID ?? "me"
    request.itemID = poi.stableID
    request.itemName = poi.name
    request.contentType = destination.favoriteContentType
    request.description_p = poi.hasDescriptionPoi ? poi.descriptionPoi : poi.description_p
    request.cityName = cityName.isEmpty ? poi.city : cityName
    if poi.hasLatitude { request.latitude = poi.latitude }
    if poi.hasLongitude { request.longitude = poi.longitude }
    request.rating = poi.rating
    request.category = poi.category
    request.llmInteractionID = poi.llmInteractionID
    if poi.hasRecommendationTrace { request.recommendationTrace = poi.recommendationTrace }
    _ = try await rpc("Could not save this place.", request) { await favorites.addToFavorites(request: $0, headers: [:]) }
  }

  /// web: TripKit → ExportItineraryToPDF with the same ExportItinerary payload,
  /// written to a temporary file for `ShareLink`.
  static func pdf(title: String, summary: String, cityName: String, groups: [DayGroup]) async throws -> URL {
    var itinerary = Loci_Export_ExportItinerary()
    itinerary.id = "trip-kit"
    itinerary.title = title
    itinerary.description_p = summary
    itinerary.cityName = cityName
    itinerary.totalDays = Int32(groups.count)
    itinerary.items = groups.flatMap { group in
      group.stops.map { stop in
        var item = Loci_Export_ExportItineraryItem()
        item.dayNumber = Int32(group.number)
        item.name = stop.name
        item.description_p = stop.hasDescriptionPoi ? stop.descriptionPoi : stop.description_p
        item.address = stop.address
        item.durationMinutes = Int32(CalendarSchedule.duration(for: stop))
        item.notes = stop.category
        return item
      }
    }
    var request = Loci_Export_ExportItineraryRequest()
    request.itinerary = itinerary
    let response = try await rpc("Could not build the PDF.", request) { await export.exportItineraryToPdf(request: $0, headers: [:]) }
    guard !response.pdfData.isEmpty else { throw APIError.custom("The PDF came back empty.") }
    let name = response.filename.isEmpty ? "loci-\(cityName.lowercased()).pdf" : response.filename
    let url = FileManager.default.temporaryDirectory.appending(path: name)
    try response.pdfData.write(to: url, options: .atomic)
    return url
  }

  /// web: /itinerary Save → BookmarkItinerary{primaryCityName, title, description, tags: [], isPublic: false}
  static func bookmark(title: String, description: String, cityName: String, sessionId: String?) async throws {
    var request = Loci_Itinerary_BookmarkRequest()
    request.primaryCityName = cityName
    request.title = title
    request.description_p = description
    request.tags = []
    request.isPublic = false
    if let sessionId { request.sessionID = sessionId }
    _ = try await rpc("Could not save to your account.", request) { await itineraries.bookmarkItinerary(request: $0, headers: [:]) }
  }
}

nonisolated extension SearchDestination {
  var favoriteContentType: Loci_Favorites_V1_ContentType {
    switch self {
    case .hotels: .hotel
    case .restaurants: .restaurant
    default: .poi
    }
  }

  /// "Hotels in Rome" (web bookmark titles for list pages).
  func bookmarkTitle(city: String) -> String {
    switch self {
    case .itinerary: "\(city) itinerary"
    case .hotels: "Hotels in \(city)"
    case .restaurants: "Restaurants in \(city)"
    case .activities: "Activities in \(city)"
    }
  }
}
