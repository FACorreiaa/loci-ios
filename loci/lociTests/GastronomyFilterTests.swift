import Foundation
import LociConnectProto
import Testing

@testable import loci

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
