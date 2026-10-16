import CoreLocation
import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

/// Taste outcomes from iOS: "Not for me" and opening a place, on the iOS
/// channel, only for places Loci recommended (web: lib/results/outcome.ts).
struct OutcomeTests {
  private func place(_ id: String, traced: Bool) -> Loci_Poi_POIDetailedInfo {
    var poi = Loci_Poi_POIDetailedInfo()
    poi.id = id
    poi.name = id
    if traced {
      var trace = Loci_Recommendation_RecommendationTrace()
      trace.runID = "run-1"
      trace.itemID = "item-\(id)"
      trace.surface = .chat
      trace.channel = .web
      poi.recommendationTrace = trace
    }
    return poi
  }

  @Test func outcomeIsNilWithoutTrace() {
    #expect(place("a", traced: false).outcome(.dismissed) == nil)
  }

  @Test func outcomeStampsIOSChannel() throws {
    let outcome = try #require(place("a", traced: true).outcome(.dismissed))
    let event = outcome.event(at: Date(timeIntervalSince1970: 1000))
    #expect(event.eventType == .dismissed)
    #expect(event.trace.channel == .ios)
    #expect(event.trace.itemID == "item-a")
    #expect(event.poiID == "a")
    #expect(!event.clientEventID.isEmpty)
    #expect(event.occurredAt.seconds == 1000)
  }

  @Test func dismissalFiltersListsAndExtrasButNotDays() {
    let groups = [DayGroup(number: 1, stops: [place("a", traced: true), place("b", traced: true)])]
    let extras = [place("x", traced: true), place("y", traced: true)]
    let dismissed: Set<String> = [place("b", traced: true).stableID, place("x", traced: true).stableID]

    let list = ResultsDismissal.apply(groups: groups, extras: extras, dismissed: dismissed, showsDays: false)
    #expect(list.groups.first?.stops.map(\.id) == ["a"])
    #expect(list.extras.map(\.id) == ["y"])

    // An itinerary's day keeps its stops: hiding one would break the plan.
    let days = ResultsDismissal.apply(groups: groups, extras: extras, dismissed: dismissed, showsDays: true)
    #expect(days.groups.first?.stops.map(\.id) == ["a", "b"])
    #expect(days.extras.map(\.id) == ["y"])
  }

  @Test func dismissingEveryStopOfAListDropsTheGroup() {
    let groups = [DayGroup(number: 1, stops: [place("a", traced: true)])]
    let result = ResultsDismissal.apply(groups: groups, extras: [], dismissed: [place("a", traced: true).stableID], showsDays: false)
    #expect(result.groups.isEmpty)
  }

  @Test func arrivalsAreVisitEventsAndManualMarksAreManual() throws {
    let visit = SpotVisit(poiID: "p", poiName: "Sé", cityName: "Lisbon", latitude: 38.71, longitude: -9.13)
    #expect(ProgressAPI.visitRequest(visit, at: CLLocation(latitude: 38.71, longitude: -9.13)).source == .visitEvent)
    var poi = place("p", traced: false)
    poi.latitude = 38.71
    poi.longitude = -9.13
    #expect(try #require(TravelHistoryAPI.manualVisitRequest(poi: poi, cityName: "Lisbon")).source == .manual)
  }
}
