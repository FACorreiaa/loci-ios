import Connect
import Foundation
import LociConnectProto
import Testing

@testable import loci

/// The trip picker for a compared hotel, the set-stay retry, and the words of
/// "Getting around from <stay>".
struct StayTransportTests {
  private func trip(_ id: String, city: String = "", cities: [String] = [], version: Int64 = 3, owned: Bool = true) -> Loci_Trip_TripDraft {
    var trip = Loci_Trip_TripDraft()
    trip.id = id
    trip.title = id
    trip.cityName = city
    trip.version = version
    trip.cities = cities.map { name in
      var city = Loci_Trip_TripCity()
      city.cityName = name
      return city
    }
    if !owned { trip.owner.id = "someone-else" }
    return trip
  }

  private var stay: Loci_Trip_TripStay {
    var stay = Loci_Trip_TripStay()
    stay.cityName = "Barcelona"
    stay.name = "Verdi 254"
    stay.address = "Carrer de Verdi 254"
    stay.priceNote = "385 euros with breakfast"
    return stay
  }

  // MARK: - Which trip

  @Test func tripsWithTheCityComeFirstAndTheRestAreGreyed() {
    let options = StayTripPicker.options(
      [
        trip("lisbon", city: "Lisbon"),
        trip("spain", city: "Madrid", cities: ["Madrid", "Barcelona"]),
        trip("friends", city: "Barcelona", owned: false),
        trip("bcn", city: "barcelona "),
      ],
      city: "Barcelona"
    )
    #expect(options.map(\.id) == ["spain", "bcn", "lisbon"])  // someone else's trip is left out
    #expect(options.map(\.isEligible) == [true, true, false])
    #expect(StayTripPicker.reason(city: "Barcelona") == "Barcelona isn't on this trip")
    #expect(StayTripPicker.planPrompt(city: "Barcelona") == "Plan a trip to Barcelona")
  }

  @Test func aCityMatchesWhateverItsCaseOrAccents() {
    #expect(StayTripPicker.matchingCity(in: trip("t", city: "Málaga"), city: "malaga") == "Málaga")
    #expect(StayTripPicker.matchingCity(in: trip("t", city: "Porto"), city: "Barcelona") == nil)
    #expect(StayTripPicker.matchingCity(in: trip("t", city: "Porto"), city: "") == nil)
  }

  @Test func setStayTakesTheTripsSpellingAndVersion() throws {
    let request = try #require(StayTripPicker.setStay(stay, on: trip("t1", city: "BARCELONA", version: 9)))
    #expect(request.tripID == "t1")
    #expect(request.baseVersion == 9)
    #expect(request.stay.cityName == "BARCELONA")
    #expect(request.stay.name == "Verdi 254")
    #expect(request.stay.priceNote == "385 euros with breakfast")
    #expect(StayTripPicker.setStay(stay, on: trip("t2", city: "Lisbon")) == nil)
    #expect(StayTripPicker.setStay(stay, on: trip("t3", city: "Barcelona", owned: false)) == nil)
  }

  // MARK: - Setting the stay

  @Test func aStaleVersionIsReadAgainAndTriedOnce() async throws {
    let service = ScriptedStayService(
      reads: [trip("t1", city: "Barcelona", version: 3), trip("t1", city: "Barcelona", version: 4)],
      sets: [.stale, .success]
    )
    let updated = try await AddStayFlow.set(stay, tripID: "t1", service: service)
    #expect(updated.version == 5)
    #expect(service.sentVersions == [3, 4])
    #expect(service.readCount == 2)
  }

  @Test func aSecondRefusalGivesUp() async {
    let service = ScriptedStayService(reads: [trip("t1", city: "Barcelona")], sets: [.stale, .stale])
    await #expect(throws: AddToTripError.staleVersion) {
      try await AddStayFlow.set(stay, tripID: "t1", service: service)
    }
    #expect(service.sentVersions.count == 2)
  }

  @Test func aCityThatLeftTheTripIsNotSent() async {
    let service = ScriptedStayService(reads: [trip("t1", city: "Lisbon")], sets: [])
    await #expect(throws: AddStayError.cityMissing("Barcelona")) {
      try await AddStayFlow.set(stay, tripID: "t1", service: service)
    }
    #expect(service.sentVersions.isEmpty)
  }

  @MainActor @Test func theStoreAddsOnlyToATripWithTheCity() async {
    let service = ScriptedStayService(
      reads: [trip("bcn", city: "Barcelona")],
      sets: [.success],
      list: [trip("lisbon", city: "Lisbon"), trip("bcn", city: "Barcelona")]
    )
    let store = StayTripPickerStore(stay: stay, hotelName: "Verdi 254", service: service)
    await store.load()
    #expect(store.phase == .loaded)
    #expect(store.hasEligibleTrip)
    #expect(await store.add(to: "lisbon") == false)
    #expect(service.sentVersions.isEmpty)
    #expect(await store.add(to: "bcn"))
    #expect(store.added?.id == "bcn")
    #expect(store.error == nil)
  }

  @MainActor @Test func noTripWithTheCityOffersToPlanOne() async {
    let service = ScriptedStayService(reads: [], sets: [], list: [trip("lisbon", city: "Lisbon")])
    let store = StayTripPickerStore(stay: stay, hotelName: "Verdi 254", service: service)
    await store.load()
    #expect(!store.hasEligibleTrip)
    #expect(store.options.count == 1)
  }

  // MARK: - Stops

  @Test func aStopSaysItsLinesAndWhetherTheWalkWasRouted() {
    let metro = HotelFixtures.stop("Fontana", mode: .metro, lines: ["L3"], minutes: 6, routed: true)
    #expect(TransitFormat.stopLine(metro) == "Fontana · L3 · 6 min walk")
    let bus = HotelFixtures.stop("Gran de Gràcia", mode: .bus, lines: ["22", "24", "V17"], minutes: 3, routed: false)
    #expect(TransitFormat.stopLine(bus) == "Gran de Gràcia · 22, 24, V17 · 3 min walk (estimate)")
    #expect(TransitFormat.spokenStopLine(bus) == "Gran de Gràcia, 22, 24, V17, 3 min walk a straight-line estimate")

    // The map has no lines for some stops, and no name for a few.
    var bare = HotelFixtures.stop("", mode: .tram, lines: [], minutes: 0, routed: false)
    #expect(TransitFormat.stopLine(bare) == "Unnamed stop")
    bare.distanceM = 350
    #expect(TransitFormat.stopLine(bare) == "Unnamed stop · 350 m (estimate)")
  }

  @Test func stopRowsNameTheirMode() {
    var transport = Loci_Trip_StayTransport()
    transport.stops = [
      HotelFixtures.stop("Fontana", mode: .metro, lines: ["L3"], minutes: 6, routed: true),
      HotelFixtures.stop("Gran de Gràcia", mode: .bus, lines: ["22"], minutes: 3, routed: false),
      HotelFixtures.stop("Somewhere", mode: .unspecified, lines: [], minutes: 9, routed: true),
    ]
    let rows = StayTransportFormat.stopRows(transport)
    #expect(rows.map(\.mode) == ["Metro", "Bus", "Stop"])
    #expect(rows[1].line == "Gran de Gràcia · 22 · 3 min walk (estimate)")
    #expect(rows[0].spoken == "Metro: Fontana, L3, 6 min walk")
  }

  @Test func titleAirportAndFootnote() {
    var transport = Loci_Trip_StayTransport()
    #expect(StayTransportFormat.title(transport, stayName: "Verdi 254") == "Getting around from Verdi 254")
    transport.stayName = "Hotel X"
    #expect(StayTransportFormat.title(transport, stayName: "Verdi 254") == "Getting around from Hotel X")
    #expect(StayTransportFormat.title(Loci_Trip_StayTransport(), stayName: "") == "Getting around from your stay")

    var airport = Loci_Trip_AirportConnection()
    airport.airportName = "Barcelona–El Prat"
    airport.iata = "BCN"
    airport.distanceKm = 14.2
    #expect(StayTransportFormat.airportLine(airport) == "BCN · 14 km")
    airport.iata = ""
    airport.distanceKm = 0
    #expect(StayTransportFormat.airportLine(airport) == "Barcelona–El Prat")

    #expect(StayTransportFormat.footnote(transport) == "No live timetables: check times before you travel.")
    transport.attribution = "Stops from OpenStreetMap"
    #expect(StayTransportFormat.footnote(transport) == "Stops from OpenStreetMap. No live timetables: check times before you travel.")
  }

  @Test func eachStatusSaysWhatItCanAndCannotTell() {
    var transport = Loci_Trip_StayTransport()
    transport.status = .noCoordinates
    #expect(StayTransportFormat.statusMessage(transport) == "We don't know where this stay is, so there's nothing to measure from.")

    transport.status = .unavailable
    #expect(StayTransportFormat.statusMessage(transport) == "The map data couldn't be reached, so nearby stops aren't shown right now.")

    transport.status = .ready
    #expect(StayTransportFormat.statusMessage(transport) == "No public transport stops are mapped within a short walk of this stay.")

    transport.stops = [HotelFixtures.stop("Fontana", mode: .metro, lines: ["L3"], minutes: 6, routed: true)]
    #expect(StayTransportFormat.statusMessage(transport) == nil)
    transport.status = .unspecified  // an older server: stops are still stops
    #expect(StayTransportFormat.statusMessage(transport) == nil)
  }

  // MARK: - Day starts

  private func start(day: String, number: Int32, minutes: Int32, routed: Bool, mode: String = "walk") -> Loci_Trip_DayStart {
    var start = Loci_Trip_DayStart()
    start.dayID = day
    start.dayNumber = number
    start.firstStopName = "Park Güell"
    start.walkMinutes = minutes
    start.routed = routed
    start.suggestedMode = mode
    start.appleDirectionsURL = "https://maps.apple.com/?daddr=41.41,2.15&dirflg=r"
    start.googleDirectionsURL = "https://www.google.com/maps/dir/?api=1&travelmode=transit"
    return start
  }

  @Test func aDayStartsWithAWalkOrASuggestion() {
    let walk = start(day: "d1", number: 1, minutes: 12, routed: true)
    #expect(StayTransportFormat.dayStartLine(walk) == "From your hotel: 12 min walk")
    #expect(!StayTransportFormat.isUnchecked(walk))
    #expect(StayTransportFormat.spokenDayStart(walk) == "From your hotel: 12 min walk, to Park Güell")

    let estimate = start(day: "d1", number: 1, minutes: 12, routed: false)
    #expect(StayTransportFormat.isUnchecked(estimate))
    #expect(StayTransportFormat.spokenDayStart(estimate)?.hasSuffix("Straight-line estimate, route not checked") == true)

    var far = start(day: "d2", number: 2, minutes: 55, routed: false, mode: "transit")
    far.distanceM = 4200
    // The distance is written the way the phone's region writes numbers.
    let km = (4.2).formatted(.number.precision(.fractionLength(1)))
    #expect(StayTransportFormat.dayStartLine(far) == "From your hotel: public transport suggested (\(km) km)")
    #expect(!StayTransportFormat.isUnchecked(far))  // nothing was estimated on foot

    #expect(StayTransportFormat.dayStartLine(start(day: "d3", number: 3, minutes: 0, routed: false)) == nil)
  }

  @Test func directionsOpenOnlyHttpsAppleFirst() {
    let both = StayTransportFormat.directions(apple: "https://maps.apple.com/?daddr=1,2", google: "https://www.google.com/maps/dir/")
    #expect(both.map(\.provider) == [.apple, .google])
    let appleOnly = StayTransportFormat.directions(apple: "https://maps.apple.com/?daddr=1,2", google: "")
    #expect(appleOnly.map(\.label) == ["Apple Maps"])
    #expect(StayTransportFormat.directions(apple: "maps://?daddr=1,2", google: "http://maps.google.com").isEmpty)
  }

  @Test func aDayIsFoundByIdThenByNumber() {
    var transport = Loci_Trip_StayTransport()
    transport.dayStarts = [start(day: "d1", number: 1, minutes: 5, routed: true), start(day: "d2", number: 2, minutes: 9, routed: true)]
    #expect(StayTransportFormat.dayStart(in: [transport], dayID: "d2", dayNumber: 7)?.walkMinutes == 9)
    // Every save renames the days: an answer read before it still matches by number.
    #expect(StayTransportFormat.dayStart(in: [transport], dayID: "d1-renamed", dayNumber: 1)?.walkMinutes == 5)
    #expect(StayTransportFormat.dayStart(in: [transport], dayID: "x", dayNumber: 3) == nil)
    #expect(StayTransportFormat.dayStart(in: [], dayID: "d1", dayNumber: 1) == nil)
  }

  // MARK: - Loading

  private func staying(_ cities: [String]) -> Loci_Trip_TripDraft {
    var trip = trip("t1", city: cities.first ?? "")
    trip.stays = cities.map { city in
      var stay = Loci_Trip_TripStay()
      stay.cityName = city
      stay.name = "Hotel in \(city)"
      return stay
    }
    var day = Loci_Trip_TripDay()
    day.id = "d1"
    day.dayNumber = 1
    trip.days = [day]
    return trip
  }

  @MainActor @Test func everyStayIsLoadedAndADayFindsItsStart() async {
    let asked = Recorder()
    let begin = start(day: "d1", number: 1, minutes: 12, routed: true)
    let model = StayTransportModel { tripID, city throws(TripRPCError) in
      await asked.add("\(tripID)|\(city)")
      var transport = Loci_Trip_StayTransport()
      transport.cityName = city
      transport.status = .ready
      if city == "Barcelona" { transport.dayStarts = [begin] }
      return transport
    }
    let trip = staying(["Barcelona", "Girona"])
    await model.load(trip)
    #expect(await asked.values == ["t1|Barcelona", "t1|Girona"])
    #expect(model.phase(for: "Girona") == .loaded({
      var transport = Loci_Trip_StayTransport()
      transport.cityName = "Girona"
      transport.status = .ready
      return transport
    }()))
    #expect(model.dayStart(for: trip.days[0])?.walkMinutes == 12)

    // A stay taken off the trip takes its section with it.
    await model.load(staying(["Girona"]))
    #expect(model.phase(for: "Barcelona") == nil)
    #expect(model.dayStart(for: trip.days[0]) == nil)
  }

  @MainActor @Test func aServerWithoutTheCallShowsNothingAndAFailureSaysSo() async {
    let missing = StayTransportModel { _, _ throws(TripRPCError) in throw TripRPCError(code: .unimplemented, message: "") }
    await missing.load(staying(["Barcelona"]))
    #expect(missing.phase(for: "Barcelona") == nil)

    let broken = StayTransportModel { _, _ throws(TripRPCError) in throw TripRPCError(code: .unavailable, message: "") }
    await broken.load(staying(["Barcelona"]))
    #expect(broken.phase(for: "Barcelona") == .failed)
  }

  @Test func theKeyChangesWithTheStayAndWithADaysFirstStop() {
    var trip = staying(["Barcelona"])
    let before = StayTransportModel.key(trip)
    #expect(StayTransportModel.key(trip) == before)
    trip.stays[0].name = "Verdi 254"
    let renamed = StayTransportModel.key(trip)
    #expect(renamed != before)
    var stop = Loci_Trip_TripStop()
    stop.name = "Park Güell"
    trip.days[0].stops = [stop]
    #expect(StayTransportModel.key(trip) != renamed)
    // A new version alone asks for nothing.
    let settled = StayTransportModel.key(trip)
    trip.version += 1
    #expect(StayTransportModel.key(trip) == settled)
  }
}

private actor Recorder {
  private(set) var values: [String] = []

  func add(_ value: String) { values.append(value) }
}

/// Reads and sets in the order a test scripts them.
private final class ScriptedStayService: StayService, @unchecked Sendable {
  enum Outcome { case success, stale }

  private let lock = NSLock()
  private var reads: [Loci_Trip_TripDraft]
  private var sets: [Outcome]
  private let list: [Loci_Trip_TripDraft]
  private var versions: [Int64] = []
  private var reading = 0

  var sentVersions: [Int64] { lock.withLock { versions } }
  var readCount: Int { lock.withLock { reading } }

  init(reads: [Loci_Trip_TripDraft], sets: [Outcome], list: [Loci_Trip_TripDraft] = []) {
    self.reads = reads
    self.sets = sets
    self.list = list
  }

  func trips() async throws -> [Loci_Trip_TripDraft] { list }

  func trip(id: String) async throws -> Loci_Trip_TripDraft {
    lock.withLock {
      reading += 1
      return reads.count > 1 ? reads.removeFirst() : reads[0]
    }
  }

  func setStay(_ request: Loci_Trip_SetStayRequest) async throws -> Loci_Trip_TripDraft {
    let next: Outcome = lock.withLock {
      versions.append(request.baseVersion)
      return sets.removeFirst()
    }
    if next == .stale { throw AddToTripError.staleVersion }
    var draft = Loci_Trip_TripDraft()
    draft.id = request.tripID
    draft.version = request.baseVersion + 1
    draft.stays = [request.stay]
    return draft
  }
}
