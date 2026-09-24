import Foundation
import LociConnectProto
import Testing

@testable import loci

/// A saved place opens on its snapshot and is filled in, never emptied, by
/// whatever the server knows.
struct SavedPlaceTests {
  private func favorite(_ id: String, kind: Loci_Favorites_V1_ContentType = .hotel) -> Loci_Favorites_V1_FavoriteItem {
    var item = Loci_Favorites_V1_FavoriteItem()
    item.id = "fav"
    item.itemID = id
    item.itemName = "Casa do Largo"
    item.contentType = kind
    item.cityName = "Lisbon"
    item.category = "Boutique"
    item.rating = 4.5
    item.latitude = 38.71
    item.longitude = -9.14
    item.description_p = "Saved description"
    return item
  }

  @Test func snapshotCarriesWhatTheFavouriteKept() {
    let stop = SavedPlace.snapshot(favorite("Casa do Largo|38.71|-9.14"))
    #expect(stop.id == "Casa do Largo|38.71|-9.14")
    #expect(stop.name == "Casa do Largo")
    #expect(stop.city == "Lisbon")
    #expect(stop.latitude == 38.71)
    #expect(stop.blurb == "Saved description")
  }

  @Test func snapshotWithoutCoordinatesLeavesThemUnset() {
    var item = favorite("x")
    item.latitude = 0
    item.longitude = 0
    #expect(!SavedPlace.snapshot(item).hasLatitude)
  }

  @Test func hotelDetailFillsInButNeverBlanks() {
    let base = SavedPlace.snapshot(favorite(UUID().uuidString))
    var hotel = Loci_Favorites_V1_HotelDetails()
    hotel.address = "Largo 3"
    hotel.contact.website = "https://example.com"
    hotel.amenities = ["wifi", "breakfast"]
    hotel.starRating = "4"
    let stop = SavedPlace.merge(hotel, onto: base)
    #expect(stop.address == "Largo 3")
    #expect(stop.website == "https://example.com")
    #expect(stop.amenities == "wifi, breakfast")
    #expect(stop.starRating == "4")
    #expect(stop.name == "Casa do Largo", "an empty name from the server keeps the saved one")
    #expect(stop.rating == 4.5)
    #expect(stop.id == base.id)
  }

  @Test func restaurantHoursAndCuisineCarryOver() {
    var restaurant = Loci_Favorites_V1_RestaurantDetails()
    restaurant.cuisineType = "Portuguese"
    restaurant.hours = ["monday": "12:00-23:00"]
    let stop = SavedPlace.merge(restaurant, onto: SavedPlace.snapshot(favorite("r", kind: .restaurant)))
    #expect(stop.cuisineType == "Portuguese")
    #expect(stop.openingHours["monday"] == "12:00-23:00")
  }

  @Test func storedPOIKeepsTheSavedIdForRemoval() {
    let savedID = UUID().uuidString
    var poi = Loci_Poi_POIDetailedInfo()
    poi.id = UUID().uuidString
    poi.name = "Casa do Largo"
    poi.address = "Largo 3"
    let stop = SavedPlace.merge(poi, onto: SavedPlace.snapshot(favorite(savedID, kind: .poi)))
    #expect(stop.id == savedID)
    #expect(stop.address == "Largo 3")
    #expect(stop.city == "Lisbon")
    #expect(stop.latitude == 38.71, "coordinates fall back to the snapshot")
  }

  @Test func kindsMapToTheirDestinations() {
    #expect(SavedPlace.destination(for: .hotel) == .hotels)
    #expect(SavedPlace.destination(for: .restaurant) == .restaurants)
    #expect(SavedPlace.destination(for: .poi) == .activities)
  }

  @Test func onlyUUIDsNameStoredPlaces() {
    #expect(SavedPlace.isStoredID(UUID().uuidString))
    #expect(!SavedPlace.isStoredID("Casa do Largo|38.71|-9.14"))
    #expect(!SavedPlace.isStoredID(""))
  }
}
