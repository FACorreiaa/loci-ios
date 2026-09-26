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

@Suite("Gastronomy filter")
struct GastronomyFilterTests {
  let porto = Loci_Gastronomy_CityGastronomy.previewPorto

  @Test func noFilterKeepsEveryDishSignatureFirst() {
    let names = GastronomyFilter().apply(to: porto).map(\.name)
    #expect(names.count == 4)
    #expect(names.prefix(2).allSatisfy { ["Francesinha", "Tripe, Porto style"].contains($0) })
  }

  @Test func filtersByCategory() {
    var filter = GastronomyFilter()
    filter.toggle(.dessert)
    #expect(filter.apply(to: porto).map(\.name) == ["Pastel de nata"])
    filter.toggle(.dessert)
    #expect(!filter.isActive)
  }

  @Test func requiresEverySelectedTag() {
    var filter = GastronomyFilter()
    filter.toggle(tag: "bread")
    #expect(Set(filter.apply(to: porto).map(\.name)) == ["Francesinha", "Bifana"])
    filter.toggle(tag: "pork")
    #expect(filter.apply(to: porto).map(\.name) == ["Bifana"])
  }

  @Test func unknownCategoryReadsAsMain() {
    var dish = Loci_Gastronomy_Dish()
    dish.category = .unspecified
    #expect(dish.displayCategory == .main)
  }

  @Test func chipsListPresentCategoriesInOrderAndTagsByFrequency() {
    #expect(porto.presentCategories == [.main, .streetFood, .dessert])
    #expect(porto.presentTags.first == "bread" || porto.presentTags.first == "meat")
  }

  @Test func mapsLinkUsesCoordinatesWhenKnown() throws {
    let exact = try #require(porto.dishes[0].places[0].mapsURL(city: "Porto"))
    #expect(exact.absoluteString.contains("ll=41.1456,-8.611"))
    let search = try #require(porto.dishes[1].places[0].mapsURL(city: "Porto"))
    #expect(search.absoluteString.contains("Casa%20Aleixo"))
  }
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
