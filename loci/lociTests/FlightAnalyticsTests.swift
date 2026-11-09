import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Same keys and values web sends (loci-client src/lib/flights/analytics.ts).
struct FlightAnalyticsTests {
  private func search(_ o: String, _ oIATA: String?, _ d: String, _ dIATA: String?) -> FlightSearch {
    var s = FlightSearch(origin: o, destination: d, departDate: "2026-12-04", passengers: 2)
    s.originIATA = oIATA
    s.destinationIATA = dIATA
    return s
  }

  @Test func builtCarriesCodesNeverNames() {
    let props = FlightAnalytics.builtProperties(.hotels, search("Lisbon", "LIS", "Barcelona", "BCN"))
    #expect(props["source"] as? String == "hotels")
    #expect(props["origin_iata"] as? String == "LIS")
    #expect(props["destination_iata"] as? String == "BCN")
    #expect(props["has_return"] as? Bool == false)
    #expect(props["passengers"] as? Int == 2)
    #expect(props["cabin"] as? String == "unspecified")
    #expect(props.count == 6)
    #expect(!props.values.contains { ($0 as? String) == "Lisbon" })
  }

  @Test func namesOnlyHaveNoCodeKeys() {
    var s = search("somewhere", nil, "Porto", nil)
    s.returnDate = "2026-12-08"
    s.cabin = .business
    let props = FlightAnalytics.builtProperties(.trip, s)
    #expect(props["origin_iata"] == nil)
    #expect(props["destination_iata"] == nil)
    #expect(props["has_return"] as? Bool == true)
    #expect(props["cabin"] as? String == "business")
  }

  @Test func openedAndClicked() {
    let opened = FlightAnalytics.openedProperties(.itinerary, destinationIATA: "BCN")
    #expect(opened as NSDictionary == ["source": "itinerary", "destination_iata": "BCN"])
    #expect(FlightAnalytics.openedProperties(.activities, destinationIATA: nil) as NSDictionary == ["source": "activities"])
    var link = Loci_Trip_FlightLink()
    link.provider = "skyscanner"
    let props = FlightAnalytics.clickedProperties(.chat, link, search("L", "LIS", "P", "OPO"))
    #expect(props as NSDictionary == ["source": "chat", "provider": "skyscanner", "origin_iata": "LIS", "destination_iata": "OPO"])
  }
}

struct FlightSearchIATATests {
  @Test func aPickedCodeTravelsUpperCasedAndATypedNameHasNone() {
    var s = FlightSearch(origin: "Lisbon", destination: "Barcelona", departDate: "2026-12-04")
    s.originIATA = "lis"
    #expect(s.originPlace.iata == "LIS")
    #expect(!s.destinationPlace.hasIata)
    s.destinationIATA = "B1"
    #expect(!s.destinationPlace.hasIata, "a malformed code is not sent")
    #expect(s.flight.origin.iata == "LIS")
  }
}
