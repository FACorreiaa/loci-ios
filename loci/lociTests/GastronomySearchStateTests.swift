import Foundation
import LociConnectProto
import Testing

@testable import loci

private func gastronomyEvent(_ g: Loci_Gastronomy_CityGastronomy, session: String = "s1", id: String) -> Loci_Chat_StreamEvent {
  var event = Loci_Chat_StreamEvent()
  event.eventID = id
  event.gastronomy.gastronomy = g
  event.gastronomy.sessionID = session
  return event
}

@Suite("Gastronomy in search results")
struct GastronomySearchStateTests {
  @Test func gastronomyEventFillsTheSection() {
    var state = SearchState()
    state.apply(Events.start("s1", domain: .itinerary, city: "Porto"))
    state.apply(gastronomyEvent(.previewPorto, id: "g1"))
    #expect(state.gastronomy?.cityName == "Porto")
    #expect(state.hasResult)
  }

  @Test func aGastronomySearchIsItsOwnAnswer() {
    var state = SearchState()
    state.apply(Events.start("s1", domain: .gastronomy, city: "Madeira"))
    #expect(state.isGastronomySearch)
    #expect(state.destination == .itinerary)
    #expect(!state.hasResult)
    state.apply(gastronomyEvent(.previewPorto, id: "g1"))
    #expect(state.hasResult)
  }

  @Test func anEmptyGastronomyIsIgnored() {
    var state = SearchState()
    state.apply(gastronomyEvent(Loci_Gastronomy_CityGastronomy(), id: "g1"))
    #expect(state.gastronomy == nil)
  }

  @Test func itineraryCarryingGastronomyIsAdoptedAndRestored() {
    var result = Loci_Chat_AiCityResponse()
    result.generalCityData.city = "Porto"
    result.gastronomy = .previewPorto
    #expect(result.hasContent)

    let restored = SearchState.restored(link: SessionLink(destination: .itinerary, sessionId: "s1", cityName: "Porto"), result: result)
    #expect(restored.gastronomy?.dishes.count == 4)
  }

  @Test func payloadCaseHasAStableName() {
    #expect(gastronomyEvent(.previewPorto, id: "g1").payload?.caseName == "gastronomy")
    #expect(Loci_Chat_DomainType.gastronomy.routeName == "gastronomy")
  }
}
