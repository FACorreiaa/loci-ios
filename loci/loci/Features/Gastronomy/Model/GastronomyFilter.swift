import Foundation
import LociConnectProto

/// The dish filter (web: DishFilter in lib/api/gastronomy.ts). Filtering is
/// local: every filter reads the one cached answer.
nonisolated struct GastronomyFilter: Equatable, Sendable {
  /// Empty means every category.
  var categories: Set<Loci_Gastronomy_DishCategory> = []
  /// A dish must carry every selected tag. Empty means no tag filter.
  var tags: Set<String> = []

  var isActive: Bool { !categories.isEmpty || !tags.isEmpty }

  mutating func toggle(_ category: Loci_Gastronomy_DishCategory) {
    if categories.remove(category) == nil { categories.insert(category) }
  }

  mutating func toggle(tag: String) {
    if tags.remove(tag) == nil { tags.insert(tag) }
  }

  /// Dishes matching the filter, signature dishes first, otherwise in the
  /// server's order.
  func apply(to gastronomy: Loci_Gastronomy_CityGastronomy) -> [Loci_Gastronomy_Dish] {
    let matching = gastronomy.dishes.filter { dish in
      (categories.isEmpty || categories.contains(dish.displayCategory)) && tags.isSubset(of: Set(dish.tags))
    }
    return matching.filter(\.isSignature) + matching.filter { !$0.isSignature }
  }
}

nonisolated extension Loci_Gastronomy_DishCategory {
  /// The order categories are offered in, as on web.
  static let displayOrder: [Loci_Gastronomy_DishCategory] = [.main, .streetFood, .snack, .dessert, .drink]

  var label: String {
    switch self {
    case .streetFood: "Street food"
    case .snack: "Snacks"
    case .dessert: "Desserts"
    case .drink: "Drinks"
    default: "Mains"
    }
  }
}

nonisolated extension Loci_Gastronomy_Dish {
  /// An unspecified or unknown category reads as a main dish, as on web.
  var displayCategory: Loci_Gastronomy_DishCategory {
    Loci_Gastronomy_DishCategory.displayOrder.contains(category) ? category : .main
  }
}

nonisolated extension Loci_Gastronomy_CityGastronomy {
  /// Categories present in the answer, in display order, for filter chips.
  var presentCategories: [Loci_Gastronomy_DishCategory] {
    Loci_Gastronomy_DishCategory.displayOrder.filter { c in dishes.contains { $0.displayCategory == c } }
  }

  /// Tags present in the answer, most common first, for filter chips.
  var presentTags: [String] {
    var counts: [String: Int] = [:]
    for dish in dishes { for tag in dish.tags { counts[tag, default: 0] += 1 } }
    return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
  }
}

nonisolated extension Loci_Gastronomy_GastronomyPlace {
  /// Apple Maps: the exact spot when the server knows it, else a search for
  /// the place in its city.
  func mapsURL(city: String) -> URL? {
    var components = URLComponents(string: "https://maps.apple.com/")
    if hasLatitude, hasLongitude {
      components?.queryItems = [URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"), URLQueryItem(name: "q", value: name)]
    } else {
      let parts = [name, address.isEmpty ? neighborhood : address, city].filter { !$0.isEmpty }
      components?.queryItems = [URLQueryItem(name: "q", value: parts.joined(separator: ", "))]
    }
    return components?.url
  }
}
