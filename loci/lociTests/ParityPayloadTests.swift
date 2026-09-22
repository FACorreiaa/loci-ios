import CoreLocation
import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Payloads that must match the web client byte for byte.
@MainActor struct ParityPayloadTests {
  /// web: routes/nearme/index.tsx searchNearby
  @Test func nearbyMessageMatchesWeb() {
    let text = NearbyView.message(radiusKm: 25, coordinate: CLLocationCoordinate2D(latitude: 38.7223, longitude: -9.1393))
    #expect(
      text
        == "Find places near me within 25 kilometers. My location is at latitude 38.722300 and longitude -9.139300. "
        + "Show me restaurants, attractions, hotels, and activities nearby."
    )
  }

  /// web: lib/compare-defaults.ts defaultWeekend — the coming Saturday, and a week ahead on a Saturday.
  @Test func defaultWeekendIsTheComingSaturday() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let wednesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23)))
    let window = CompareView.defaultWeekend(now: wednesday, calendar: calendar)
    #expect(calendar.component(.day, from: window.start) == 26)
    #expect(calendar.component(.weekday, from: window.start) == 7)
    #expect(calendar.dateComponents([.day], from: window.start, to: window.end).day == 1)

    let saturday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 10)))
    let next = CompareView.defaultWeekend(now: saturday, calendar: calendar)
    #expect(calendar.component(.day, from: next.start) == 3)
    #expect(calendar.component(.month, from: next.start) == 10)
  }

  @Test func allPlacesMergesEveryListWithoutRepeats() {
    var state = SearchState()
    state.apply(Events.start("s1", domain: .general))
    state.apply(Events.hotels(["Hotel A"], id: "e1"))
    var restaurants = Loci_Chat_StreamEvent()
    restaurants.eventID = "e2"
    var poi = Loci_Poi_POIDetailedInfo()
    poi.name = "Hotel A"
    restaurants.restaurants.pois = [poi]
    state.apply(restaurants)
    #expect(state.allPlaces.count == 1)
  }
}
