import Connect
import CoreLocation
import Foundation
import LociConnectProto
import Testing

@testable import loci

private func place(_ name: String, id: String = "", lat: Double? = nil, lon: Double? = nil, category: String = "", rating: Double = 0) -> Loci_Poi_POIDetailedInfo {
  var p = Loci_Poi_POIDetailedInfo()
  p.id = id
  p.name = name
  p.category = category
  p.rating = rating
  if let lat, let lon {
    p.latitude = lat
    p.longitude = lon
  }
  return p
}

private func stop(_ id: String, _ name: String, order: Int, poiID: String = "") -> Loci_Trip_TripStop {
  var s = Loci_Trip_TripStop()
  s.id = id
  s.name = name
  s.orderIndex = Int32(order)
  s.poiID = poiID
  return s
}

private func trip(_ days: [[Loci_Trip_TripStop]], version: Int64 = 1) -> Loci_Trip_TripDraft {
  var t = Loci_Trip_TripDraft()
  t.id = "trip-1"
  t.version = version
  t.days = days.enumerated().map { offset, stops in
    var day = Loci_Trip_TripDay()
    day.id = "day-\(offset + 1)"
    day.dayNumber = Int32(offset + 1)
    day.stops = stops
    return day
  }
  return t
}

private let lisbon = CLLocationCoordinate2D(latitude: 38.7139, longitude: -9.1335)
/// About 1.1 km north per 0.01 degree of latitude.
private func north(_ degrees: Double) -> (Double, Double) { (lisbon.latitude + degrees, lisbon.longitude) }

struct TripBackedDaysTests {
  @Test func tripDecidesTheStopsAndTheirOrder() {
    let generated = [place("Sé de Lisboa", id: "p1", rating: 4.6), place("Castelo", id: "p2"), place("Miradouro", id: "p3")]
    let backed = TripBackedDays.build(
      trip: trip([[stop("s2", "Castelo", order: 0, poiID: "p2"), stop("s1", "se de lisboa", order: 1)], [stop("s9", "Tasca do Zé", order: 0)]]),
      generated: generated
    )
    #expect(backed.groups.map { $0.stops.map(\.name) } == [["Castelo", "Sé de Lisboa"], ["Tasca do Zé"]])
    // Matched by name, the generated card keeps its rating.
    #expect(backed.groups[0].stops[1].rating == 4.6)
    #expect(backed.extras.map(\.name) == ["Miradouro"])
    #expect(backed.days == [TripDayRef(id: "day-1", number: 1), TripDayRef(id: "day-2", number: 2)])
    #expect(backed.refs["p1"] == TripStopRef(stopID: "s1", dayID: "day-1", index: 1, count: 2))
  }

  @Test func aStopTheGenerationNeverSawKeepsItsOwnPin() {
    var added = stop("s1", "Pasted place", order: 0)
    added.latitude = 38.7
    added.longitude = -9.1
    added.address = "Rua A"
    let card = TripBackedDays.build(trip: trip([[added]]), generated: []).groups[0].stops[0]
    #expect(card.name == "Pasted place")
    #expect(card.latitude == 38.7)
    #expect(card.address == "Rua A")
    #expect(card.stableID == "trip-stop-s1")
  }

  @Test func aPlaceOnTheTripTwiceGetsTwoCards() {
    let backed = TripBackedDays.build(
      trip: trip([[stop("s1", "Castelo", order: 0, poiID: "p2"), stop("s2", "Castelo", order: 1, poiID: "p2")]]),
      generated: [place("Castelo", id: "p2")]
    )
    #expect(Set(backed.groups[0].stops.map(\.stableID)).count == 2)
    #expect(backed.refs.count == 2)
  }

  @Test func googlePlaceLinkIsByNameAndCity() {
    #expect(
      GoogleMapsRoute.placeURL(name: "Sé de Lisboa", city: "Lisbon")?.absoluteString
        == "https://www.google.com/maps/search/?api=1&query=S%C3%A9%20de%20Lisboa%2C%20Lisbon"
    )
    #expect(GoogleMapsRoute.placeURL(name: "Castelo", city: "")?.absoluteString == "https://www.google.com/maps/search/?api=1&query=Castelo")
    #expect(GoogleMapsRoute.placeURL(name: "  ", city: "Lisbon") == nil)
  }
}

struct EatNearbyTests {
  @Test func nearestFirstInsideTheRadiusWithoutWhatTheTripHas() {
    let far = north(0.02)
    let near = north(0.001)
    let mid = north(0.004)
    let options = EatNearby.options(
      around: lisbon,
      places: [
        place("Far", lat: far.0, lon: far.1), place("Mid", lat: mid.0, lon: mid.1), place("Near", lat: near.0, lon: near.1),
        place("On trip", id: "p1", lat: near.0, lon: near.1), place("Nowhere"),
      ],
      onTrip: [place("on TRIP", id: "p1")]
    )
    #expect(options.map(\.place.name) == ["Near", "Mid"])
    #expect(options[0].walkMinutes == 1)
    #expect(options[1].walkMinutes == 6)
  }

  @Test func saysHowLittleItKnows() {
    #expect(EatNearby.summary(count: 0, stopName: "Castelo").contains("doesn't know anywhere"))
    #expect(EatNearby.summary(count: 1, stopName: "Castelo") == "Loci only knows 1 place to eat near Castelo.")
    #expect(EatNearby.summary(count: 5, stopName: "Castelo") == "Places Loci knows near Castelo")
    #expect(
      EatNearby.googleURL(stopName: "Castelo", city: "Lisbon")?.absoluteString
        == "https://www.google.com/maps/search/?api=1&query=restaurants%20near%20Castelo%2C%20Lisbon"
    )
  }
}

struct DaySuggestionsTests {
  @Test func extrasFirstThenNearbyByRating() {
    let a = north(0.005)
    let b = north(0.002)
    let c = north(0.004)
    let picks = DaySuggestions.pick(
      centroid: lisbon,
      onTrip: [],
      extras: [place("Extra", lat: a.0, lon: a.1, rating: 3.9)],
      nearby: [place("Ok museum", lat: b.0, lon: b.1, rating: 4.1), place("Great museum", lat: c.0, lon: c.1, rating: 4.8)]
    )
    #expect(picks.map(\.name) == ["Extra", "Great museum", "Ok museum"])
  }

  @Test func leavesOutTheTripFoodRepeatsAndAnythingTooFar() {
    let near = north(0.001)
    let far = north(0.05)
    let picks = DaySuggestions.pick(
      centroid: lisbon,
      onTrip: [place("Sé de Lisboa")],
      extras: [
        place("se de lisboa", lat: near.0, lon: near.1), place("Far extra", lat: far.0, lon: far.1),
        place("Tasca", lat: near.0, lon: near.1, category: "Restaurant"), place("Viewpoint", lat: near.0, lon: near.1), place("Nowhere"),
      ],
      nearby: [place("viewpoint", lat: near.0, lon: near.1), place("Coffee", lat: near.0, lon: near.1, category: "cafe")]
    )
    #expect(picks.map(\.name) == ["Viewpoint"])
  }

  @Test func aDayWithNoPositionTakesExtrasAsTheyCome() {
    let picks = DaySuggestions.pick(centroid: nil, onTrip: [], extras: (0..<9).map { place("E\($0)") }, nearby: [])
    #expect(picks.map(\.name) == ["E0", "E1", "E2", "E3"])
    #expect(DaySuggestions.centroid(of: [place("A"), place("B", lat: 0, lon: 0)]) == nil)
  }
}

@MainActor struct TripEditSessionTests {
  /// What the edit client was asked to do, in order.
  private actor Calls {
    var log: [String] = []

    func add(_ call: String) { log.append(call) }
  }

  private func client(calls: Calls, current: Loci_Trip_TripDraft, conflictOnce: Bool = false) -> TripEditClient {
    let failed = Calls()
    return TripEditClient(
      trip: { _ throws(TripRPCError) in
        await calls.add("get")
        var latest = current
        latest.version = 9
        return latest
      },
      tripForSession: { session throws(TripRPCError) in
        await calls.add("session:\(session)")
        return current
      },
      reorder: { _, day, ids, version throws(TripRPCError) in
        await calls.add("reorder:\(day):\(ids.joined(separator: ",")):v\(version)")
        if conflictOnce, await failed.log.isEmpty {
          await failed.add("x")
          throw TripRPCError(code: .failedPrecondition, message: "version conflict")
        }
        var next = current
        next.version = version + 1
        return next
      },
      move: { _, stop, day, index, _ throws(TripRPCError) in
        await calls.add("move:\(stop)->\(day)@\(index)")
        return current
      },
      remove: { _, stop, _ throws(TripRPCError) in
        await calls.add("remove:\(stop)")
        return current
      },
      add: { _, day, stop, after, _ throws(TripRPCError) in
        await calls.add("add:\(stop.name)->\(day) after \(after ?? "-")")
        return current
      }
    )
  }

  private var twoDays: Loci_Trip_TripDraft {
    trip([[stop("a", "A", order: 0), stop("b", "B", order: 1)], [stop("c", "C", order: 0)]], version: 3)
  }

  @Test func findsTheTripByItsSessionWhenThePageHasNoTripID() async {
    let calls = Calls()
    let session = TripEditSession(client: client(calls: calls, current: twoDays))
    await session.load(tripID: nil, sessionID: "sess-1")
    #expect(await calls.log == ["session:sess-1"])
    #expect(session.trip?.id == "trip-1")
    #expect(session.canEdit)
  }

  @Test func editsCarryTheVersionTheTripWasReadAt() async {
    let calls = Calls()
    let session = TripEditSession(client: client(calls: calls, current: twoDays))
    await session.load(tripID: nil, sessionID: "sess-1")
    #expect(await session.nudge(stopID: "b", up: true))
    #expect(session.trip?.version == 4)
    // Already first: nothing is sent.
    #expect(await session.nudge(stopID: "a", up: true) == false)
    #expect(await session.move(stopID: "a", toDayID: "day-2"))
    #expect(await session.add(TripEdits.stop(named: "Coffee"), dayID: "day-1", afterStopID: "a"))
    #expect(await calls.log == ["session:sess-1", "reorder:day-1:b,a:v3", "move:a->day-2@1", "add:Coffee->day-1 after a"])
  }

  @Test func aConflictReloadsAndSaysSoInsteadOfOverwriting() async {
    let calls = Calls()
    let session = TripEditSession(client: client(calls: calls, current: twoDays, conflictOnce: true))
    await session.load(tripID: nil, sessionID: "sess-1")
    #expect(await session.nudge(stopID: "b", up: true) == false)
    #expect(session.notice == TripEditSession.conflictNotice)
    #expect(session.trip?.version == 9)
    #expect(await calls.log.last == "get")
  }

  @Test func someoneElsesTripIsNotEditedHere() async {
    var shared = twoDays
    shared.owner.id = "someone-else"
    let calls = Calls()
    let session = TripEditSession(client: client(calls: calls, current: shared))
    await session.load(tripID: nil, sessionID: "sess-1")
    #expect(session.canEdit == false)
    #expect(await session.remove(stopID: "a") == false)
    #expect(await calls.log == ["session:sess-1"])
  }

  @Test func aPlaceLociLacksGoesInWithItsOwnPin() {
    let known = TripEdits.stop(from: place("Castelo", id: "0b1e7c1e-6f0a-4d3b-9a55-2f6f3c1d9e10", lat: 38.7, lon: -9.1))
    #expect(known.poiID == "0b1e7c1e-6f0a-4d3b-9a55-2f6f3c1d9e10")
    #expect(known.latitude == 38.7)
    let unknown = TripEdits.stop(from: place("Corner bar"))
    #expect(unknown.poiID.isEmpty)
    #expect(unknown.hasLatitude == false)
  }
}
