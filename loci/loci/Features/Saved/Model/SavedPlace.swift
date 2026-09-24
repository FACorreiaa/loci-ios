import Foundation
import LociConnectProto

/// A saved place as the detail view reads it. The favourite's own snapshot is
/// shown at once; the stored place, when the server has one, fills in the rest.
/// Every kind ends up as a `Loci_Poi_POIDetailedInfo`, so saved places and
/// search results share one detail view.
nonisolated enum SavedPlace {
  /// What the favourite itself kept: enough to show a name, a pin and a note.
  static func snapshot(_ item: Loci_Favorites_V1_FavoriteItem) -> Loci_Poi_POIDetailedInfo {
    var stop = Loci_Poi_POIDetailedInfo()
    stop.id = item.itemID
    stop.name = item.itemName
    stop.city = item.cityName
    stop.category = item.category
    stop.description_p = item.description_p
    stop.rating = item.rating
    if item.latitude != 0 || item.longitude != 0 {
      stop.latitude = item.latitude
      stop.longitude = item.longitude
    }
    return stop
  }

  static func destination(for contentType: Loci_Favorites_V1_ContentType) -> SearchDestination {
    switch contentType {
    case .hotel: .hotels
    case .restaurant: .restaurants
    default: .activities
    }
  }

  static func kindLabel(_ contentType: Loci_Favorites_V1_ContentType) -> String {
    switch contentType {
    case .hotel: "Hotel"
    case .restaurant: "Restaurant"
    case .itinerary: "Itinerary"
    default: "Place"
    }
  }

  static func kindSymbol(_ contentType: Loci_Favorites_V1_ContentType) -> String {
    switch contentType {
    case .hotel: "bed.double"
    case .restaurant: "fork.knife"
    case .itinerary: "map"
    default: "mappin.and.ellipse"
    }
  }

  /// Only a UUID names a stored POI; older saves were keyed by name, and a place
  /// with no id is saved as "name|lat|lon".
  static func isStoredID(_ id: String) -> Bool { UUID(uuidString: id) != nil }

  // MARK: - Enrichment. Empty values never overwrite what the snapshot knew.

  static func merge(_ hotel: Loci_Favorites_V1_HotelDetails, onto base: Loci_Poi_POIDetailedInfo) -> Loci_Poi_POIDetailedInfo {
    var stop = base
    fill(&stop.name, hotel.name)
    fill(&stop.city, hotel.city)
    fill(&stop.category, hotel.category)
    fill(&stop.description_p, hotel.description_p)
    fill(&stop.address, hotel.address)
    fill(&stop.phoneNumber, hotel.phone.isEmpty ? hotel.contact.phone : hotel.phone)
    fill(&stop.website, hotel.website.isEmpty ? hotel.contact.website : hotel.website)
    fill(&stop.priceRange, hotel.priceRange.isEmpty ? hotel.pricePerNight : hotel.priceRange)
    if !hotel.starRating.isEmpty { stop.starRating = hotel.starRating }
    if hotel.rating > 0 { stop.rating = hotel.rating }
    if !hotel.images.isEmpty { stop.images = hotel.images }
    if !hotel.amenities.isEmpty { stop.amenities = hotel.amenities.joined(separator: ", ") }
    if !hotel.features.isEmpty { stop.tags = hotel.features }
    place(&stop, hotel.latitude, hotel.longitude)
    return stop
  }

  static func merge(_ restaurant: Loci_Favorites_V1_RestaurantDetails, onto base: Loci_Poi_POIDetailedInfo) -> Loci_Poi_POIDetailedInfo {
    var stop = base
    fill(&stop.name, restaurant.name)
    fill(&stop.city, restaurant.city)
    fill(&stop.category, restaurant.category)
    fill(&stop.description_p, restaurant.description_p)
    fill(&stop.address, restaurant.address)
    fill(&stop.phoneNumber, restaurant.phone.isEmpty ? restaurant.contact.phone : restaurant.phone)
    fill(&stop.website, restaurant.website.isEmpty ? restaurant.contact.website : restaurant.website)
    fill(&stop.priceRange, restaurant.priceRange.isEmpty ? restaurant.averagePrice : restaurant.priceRange)
    if !restaurant.cuisineType.isEmpty { stop.cuisineType = restaurant.cuisineType }
    if restaurant.rating > 0 { stop.rating = restaurant.rating }
    if !restaurant.images.isEmpty { stop.images = restaurant.images }
    if !restaurant.tags.isEmpty { stop.tags = restaurant.tags }
    if !restaurant.hours.isEmpty { stop.openingHours = restaurant.hours }
    place(&stop, restaurant.latitude, restaurant.longitude)
    return stop
  }

  /// A stored POI is already the right shape; keep the saved id, which is what
  /// removing the favourite matches on, and whatever the snapshot knew that it does not.
  static func merge(_ poi: Loci_Poi_POIDetailedInfo, onto base: Loci_Poi_POIDetailedInfo) -> Loci_Poi_POIDetailedInfo {
    var stop = poi
    stop.id = base.id
    fill(&stop.name, base.name)
    fill(&stop.city, base.city)
    fill(&stop.category, base.category)
    if stop.blurb.isEmpty { stop.description_p = base.description_p }
    if stop.rating == 0 { stop.rating = base.rating }
    if !stop.hasLatitude || !stop.hasLongitude || (stop.latitude == 0 && stop.longitude == 0) {
      if base.hasLatitude { stop.latitude = base.latitude }
      if base.hasLongitude { stop.longitude = base.longitude }
    }
    return stop
  }

  private static func fill(_ field: inout String, _ value: String) {
    if !value.isEmpty { field = value }
  }

  private static func place(_ stop: inout Loci_Poi_POIDetailedInfo, _ lat: Double, _ lon: Double) {
    guard lat != 0 || lon != 0 else { return }
    stop.latitude = lat
    stop.longitude = lon
  }
}

/// The reads behind a saved place. Each returns nil rather than throwing: a
/// place that cannot be enriched still shows what was saved.
nonisolated enum SavedPlaceAPI {
  private static let poi = Loci_Poi_PoiserviceClient(client: ConnectTransport.shared.protocolClient)

  static func enrich(_ item: Loci_Favorites_V1_FavoriteItem, base: Loci_Poi_POIDetailedInfo) async -> Loci_Poi_POIDetailedInfo? {
    switch item.contentType {
    case .hotel:
      // The server falls back to this user's saved snapshot for ids it has no
      // hotel for, so any id is worth asking about.
      var request = Loci_Favorites_V1_GetHotelDetailsRequest()
      request.hotelID = item.itemID
      guard let response = try? await rpc("Could not load this hotel.", request, {
        await SavedAPI.favorites.getHotelDetails(request: $0, headers: [:])
      }), response.hasHotel else { return nil }
      return SavedPlace.merge(response.hotel, onto: base)
    case .restaurant:
      var request = Loci_Favorites_V1_GetRestaurantDetailsRequest()
      request.restaurantID = item.itemID
      guard let response = try? await rpc("Could not load this restaurant.", request, {
        await SavedAPI.favorites.getRestaurantDetails(request: $0, headers: [:])
      }), response.hasRestaurant else { return nil }
      return SavedPlace.merge(response.restaurant, onto: base)
    default:
      guard SavedPlace.isStoredID(item.itemID) else { return nil }
      var request = Loci_Poi_GetPOIRequest()
      request.poiID = item.itemID
      guard let response = try? await rpc("Could not load this place.", request, {
        await poi.getPoi(request: $0, headers: [:])
      }), response.hasPoi else { return nil }
      return SavedPlace.merge(response.poi, onto: base)
    }
  }

  /// web: FavoriteButton unsave → RemoveFromFavorites{itemId, contentType}
  static func remove(_ item: Loci_Favorites_V1_FavoriteItem) async throws {
    var request = Loci_Favorites_V1_RemoveFromFavoritesRequest()
    request.userID = await AuthSessionManager.shared.currentUserID ?? "me"
    request.itemID = item.itemID
    request.contentType = item.contentType
    _ = try await rpc("Could not remove it.", request) { await SavedAPI.favorites.removeFromFavorites(request: $0, headers: [:]) }
  }

  /// Saves it again under the same id and kind, so undoing a removal restores the same row.
  static func restore(_ item: Loci_Favorites_V1_FavoriteItem) async throws {
    var request = Loci_Favorites_V1_AddToFavoritesRequest()
    request.userID = await AuthSessionManager.shared.currentUserID ?? "me"
    request.itemID = item.itemID
    request.itemName = item.itemName
    request.contentType = item.contentType
    request.description_p = item.description_p
    request.notes = item.notes
    request.cityName = item.cityName
    request.latitude = item.latitude
    request.longitude = item.longitude
    request.rating = item.rating
    request.category = item.category
    _ = try await rpc("Could not save it again.", request) { await SavedAPI.favorites.addToFavorites(request: $0, headers: [:]) }
  }
}
