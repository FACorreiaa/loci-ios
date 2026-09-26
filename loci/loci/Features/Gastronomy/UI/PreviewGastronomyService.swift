import Foundation
import LociConnectProto

/// Offline sample data for `-designPreview gastronomy` and previews.
nonisolated struct PreviewGastronomyService: GastronomyService {
  func city(named name: String) async throws -> Loci_Gastronomy_CityGastronomy { .previewPorto }
}

nonisolated extension Loci_Gastronomy_CityGastronomy {
  static var previewPorto: Loci_Gastronomy_CityGastronomy {
    var g = Loci_Gastronomy_CityGastronomy()
    g.cityName = "Porto"
    g.country = "Portugal"
    g.overview = "Porto eats like a port city with a northern appetite: pork and bread, salt cod in a hundred ways, "
      + "tripe that gave the townspeople their nickname, and port wine aged across the river in Gaia."
    g.culinaryTraditions = ["Tripeiros: the nickname comes from the tripe the city kept when its meat went to the fleet."]
    g.diningTips = ["Lunch runs 12:30–15:00; many tascas close between services."]

    var francesinha = Loci_Gastronomy_Dish.preview("Francesinha", .main, tags: ["meat", "cheese", "bread"])
    francesinha.isSignature = true
    francesinha.description_p = "Steak, sausage and ham under melted cheese and a beer-and-tomato sauce."
    francesinha.places = [.preview("Café Santiago", in: "Bolhão", why: "Many locals' benchmark since 1959.", at: (41.1456, -8.611))]

    var tripe = Loci_Gastronomy_Dish.preview("Tripe, Porto style", .main, tags: ["meat"])
    tripe.localName = "Tripas à moda do Porto"
    tripe.isSignature = true
    tripe.description_p = "A slow stew of tripe, white beans, chouriço and rice."
    tripe.places = [.preview("Casa Aleixo", in: "Campanhã", why: "Family-run since 1948.")]

    var bifana = Loci_Gastronomy_Dish.preview("Bifana", .streetFood, tags: ["pork", "bread"])
    bifana.description_p = "Thin pork steak simmered in garlic and wine, in a soft roll."
    bifana.places = [.preview("Conga", in: "Baixa", why: "Open late, spicy sauce.")]

    var nata = Loci_Gastronomy_Dish.preview("Pastel de nata", .dessert, tags: ["pastry", "vegetarian"])
    nata.description_p = "Custard tart with a blistered top, best warm."
    nata.places = [.preview("Manteigaria", in: "Bolhão", why: "A bell rings for each batch.")]

    g.dishes = [francesinha, tripe, bifana, nata]
    return g
  }
}

nonisolated extension Loci_Gastronomy_Dish {
  static func preview(_ name: String, _ category: Loci_Gastronomy_DishCategory, tags: [String]) -> Loci_Gastronomy_Dish {
    var dish = Loci_Gastronomy_Dish()
    dish.name = name
    dish.category = category
    dish.tags = tags
    return dish
  }
}

nonisolated extension Loci_Gastronomy_GastronomyPlace {
  static func preview(_ name: String, in neighborhood: String, why: String, at position: (Double, Double)? = nil) -> Loci_Gastronomy_GastronomyPlace {
    var place = Loci_Gastronomy_GastronomyPlace()
    place.name = name
    place.neighborhood = neighborhood
    place.whyFamous = why
    place.priceRange = "€€"
    if let position {
      place.latitude = position.0
      place.longitude = position.1
    }
    return place
  }
}
