import LociConnectProto
import Testing

@testable import loci

struct TripPlanTests {
  private func trip(city: String = "Lisbon", days: [Loci_Trip_TripDay], cities: [String] = []) -> Loci_Trip_TripDraft {
    var t = Loci_Trip_TripDraft()
    t.cityName = city
    t.days = days
    t.cities = cities.map { name in var c = Loci_Trip_TripCity(); c.cityName = name; return c }
    return t
  }

  private func day(_ city: String, lat: Double? = nil, lon: Double? = nil) -> Loci_Trip_TripDay {
    var d = Loci_Trip_TripDay()
    d.cityName = city
    if let lat { d.cityLat = lat }
    if let lon { d.cityLon = lon }
    return d
  }

  @Test func citiesAreTheMultiCityListElseTheTripsCity() {
    #expect(TripPlan.cities(of: trip(days: [])) == ["Lisbon"])
    #expect(TripPlan.cities(of: trip(days: [], cities: ["Lisbon", "Porto"])) == ["Lisbon", "Porto"])
  }

  @Test func coordinateIsTheFirstDaySpentThere() {
    let t = trip(days: [day("Lisbon"), day("Porto", lat: 41.1, lon: -8.6), day("", lat: 38.7, lon: -9.1)])
    #expect(TripPlan.coordinate(of: "Porto", in: t)?.latitude == 41.1)
    #expect(TripPlan.coordinate(of: "lisbon", in: t)?.latitude == 38.7, "an unnamed day is the trip's own city")
    #expect(TripPlan.coordinate(of: "Faro", in: t) == nil)
    #expect(TripPlan.coordinate(of: "Lisbon", in: trip(days: [day("Lisbon")])) == nil, "no position, no search")
  }

  @Test func starsReadNumbersBeforeGlyphs() {
    #expect(TripPlan.stars("4") == 4)
    #expect(TripPlan.stars("4.5") == 4.5)
    #expect(TripPlan.stars("4★") == 4)
    #expect(TripPlan.stars("★★★") == 3)
    #expect(TripPlan.stars("") == nil)
    #expect(TripPlan.stars("luxury") == nil)
  }

  @Test func hotelsFilterToTheWholeStarBestRatedFirst() {
    func hotel(_ name: String, _ stars: String, _ rating: Double) -> Loci_Favorites_V1_HotelDetails {
      var h = Loci_Favorites_V1_HotelDetails()
      h.name = name
      h.starRating = stars
      h.rating = rating
      return h
    }
    let all = [hotel("A", "5", 4.8), hotel("B", "4.5", 4.2), hotel("C", "", 4.9), hotel("D", "4", 4.6)]
    #expect(TripPlan.hotels(all, stars: 4).map(\.name) == ["D", "B"])
    #expect(TripPlan.hotels(all, stars: 0).map(\.name) == ["C", "A", "D", "B"], "any keeps unrated")
  }
}
