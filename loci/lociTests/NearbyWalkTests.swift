import CoreLocation
import Foundation
import LociConnectProto
import Testing

@testable import loci

@MainActor struct NearbyWalkTests {
  private func poi(_ name: String, _ lat: Double, _ lon: Double, id: String = "") -> Loci_Poi_POIDetailedInfo {
    var poi = Loci_Poi_POIDetailedInfo()
    poi.id = id
    poi.name = name
    poi.latitude = lat
    poi.longitude = lon
    return poi
  }

  @Test func fencesTheNearestTwentyWithoutRepeats() {
    let here = CLLocationCoordinate2D(latitude: 41.15, longitude: -8.61)
    var places = (0..<30).map { poi("Place \($0)", 41.15 + Double($0) * 0.001, -8.61, id: "p\($0)") }
    places.append(poi("Place 0", 41.15, -8.61, id: "p0"))  // a repeat
    var noCoordinates = Loci_Poi_POIDetailedInfo()
    noCoordinates.name = "No pin"
    places.append(noCoordinates)

    let chosen = POIProximityMonitor.select(places: places, from: here)

    #expect(chosen.count == POIProximityMonitor.maxConditions)
    #expect(chosen.first?.name == "Place 0")
    #expect(chosen.last?.name == "Place 19")
    #expect(Set(chosen.map(\.stableID)).count == chosen.count)
    #expect(!chosen.contains { $0.name == "No pin" })
  }

  @Test func nearestPlaceUsesRealDistance() throws {
    let here = CLLocationCoordinate2D(latitude: 41.1496, longitude: -8.6109)  // Porto
    let places = [poi("Lisbon", 38.7223, -9.1393), poi("Bolhão", 41.1496, -8.6070), poi("Gaia", 41.1339, -8.6099)]
    let nearest = try #require(NearbyWalk.nearest(of: places, to: here))
    #expect(nearest.name == "Bolhão")
    #expect(nearest.meters > 300 && nearest.meters < 400)
    #expect(NearbyWalk.nearest(of: places, to: nil) == nil)
  }

  @Test func liveActivityTextIsSharedWithTheWidget() {
    let state = NearbyWalkAttributes.ContentState(steps: 1840, distanceMeters: 1234, placesNearby: 4, nearestName: "Bolhão", nearestMeters: 40)
    // Grouping follows the device locale ("1,840" or "1 840"); the suffix and pluralisation are ours.
    #expect(state.stepsText == 1840.formatted(.number) + " steps")
    #expect(state.distanceText == "1.2 km")
    #expect(state.nearestText == "Bolhão · 40 m")
    #expect(NearbyWalkAttributes.ContentState(steps: 1, distanceMeters: 999.4, placesNearby: 0).stepsText == "1 step")
    #expect(NearbyWalkAttributes.ContentState.format(meters: 999.4) == "999 m")
  }
}
