import LociConnectProto
import Testing

@testable import loci

struct FlightSearchTests {
  @Test func readyNeedsBothPlacesADateAndAReturnNotBeforeIt() {
    var s = FlightSearch(origin: " London ", destination: "Lisbon", departDate: "2026-11-12")
    #expect(s.isReady)
    s.returnDate = "2026-11-11"
    #expect(!s.isReady, "a return before the departure")
    s.returnDate = "2026-11-17"
    #expect(s.isReady)
    s.origin = "  "
    #expect(!s.isReady)
  }

  @Test func theSavedFlightIsTrimmedAndOneWayHasNoReturn() {
    let f = FlightSearch(origin: " London ", destination: "Lisbon", departDate: "2026-11-12", passengers: 2).flight
    #expect(f.origin.name == "London")
    #expect(!f.hasReturnDate)
    #expect(f.passengers == 2)
  }
}
