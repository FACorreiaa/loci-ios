import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Compare's "Save as trip" builds the TripDraft web builds (routes/compare).
/// `user_id` is validated non-empty server-side (the handler still takes the
/// caller from the token), so an empty id used to fail every save.
struct CompareTripBuilderTests {
  private func column(_ name: String, id: String = "", pois: [String] = []) -> Loci_Compare_V1_CityCompareColumn {
    var c = Loci_Compare_V1_CityCompareColumn()
    c.cityName = name
    c.cityID = id
    c.topPois = pois.map { n in
      var p = Loci_Poi_POIDetailedInfo()
      p.id = "poi-\(n)"
      p.name = n
      return p
    }
    return c
  }

  @Test func weekendTripCarriesTheSessionUser() {
    let trip = CompareTripBuilder.weekend(column: column("Évora"), dual: false, columns: [], userID: "user-1")
    #expect(trip.userID == "user-1")
  }

  @Test func weekendTripFallsBackToSelfWhenNoUserIDIsKnown() {
    #expect(CompareTripBuilder.weekend(column: column("Évora"), dual: false, columns: [], userID: nil).userID == "self")
    #expect(CompareTripBuilder.weekend(column: column("Évora"), dual: false, columns: [], userID: "").userID == "self")
  }

  @Test func weekendTripKeepsTwoStopsPerCityAndADayPerCityWhenDual() {
    let a = column("Évora", id: "c-1", pois: ["A1", "A2", "A3"])
    let b = column("Beja", pois: ["B1"])
    let trip = CompareTripBuilder.weekend(column: a, dual: true, columns: [a, b], userID: "u")
    #expect(trip.title == "Weekend: Évora + Beja")
    #expect(trip.cityName == "Évora")
    #expect(trip.cityID == "c-1")
    #expect(trip.days.map(\.dayNumber) == [1, 2])
    #expect(trip.days[0].stops.map(\.name) == ["A1", "A2"])
    #expect(trip.days[1].stops.map(\.name) == ["B1"])
    #expect(trip.days[1].stops[0].orderIndex == 0)
  }

  @Test func singleWeekendTripIsOneDay() {
    let a = column("Évora", pois: ["A1", "A2", "A3"])
    let trip = CompareTripBuilder.weekend(column: a, dual: false, columns: [a], userID: "u")
    #expect(trip.title == "Évora weekend")
    #expect(trip.days.count == 1)
    #expect(trip.days[0].stops.map(\.name) == ["A1", "A2"])
  }

  @Test func multiCityTripSetsUserAndOrdersDays() {
    var plan = Loci_Compare_V1_MultiCityPlan()
    var lisbon = Loci_Compare_V1_PlannedCity()
    lisbon.cityName = "Lisbon"
    lisbon.cityID = "c-lis"
    lisbon.dayNumbers = [3]
    lisbon.lat = 38.7
    lisbon.lon = -9.1
    var porto = Loci_Compare_V1_PlannedCity()
    porto.cityName = "Porto"
    porto.dayNumbers = [1, 2]
    plan.cities = [lisbon, porto]
    let trip = CompareTripBuilder.multiCity(plan: plan, userID: nil)
    #expect(trip?.userID == "self")
    #expect(trip?.title == "Lisbon + Porto")
    #expect(trip?.cityName == "Lisbon")
    #expect(trip?.cityID == "c-lis")
    #expect(trip?.days.map(\.dayNumber) == [1, 2, 3])
    #expect(trip?.days.map(\.cityName) == ["Porto", "Porto", "Lisbon"])
    #expect(trip?.days[2].cityLat == 38.7)
  }

  @Test func multiCityTripNeedsACity() {
    #expect(CompareTripBuilder.multiCity(plan: Loci_Compare_V1_MultiCityPlan(), userID: "u") == nil)
  }
}
