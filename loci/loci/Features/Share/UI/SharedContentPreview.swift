import LociConnectProto
import SwiftUI

/// `-designPreview sharedPlace | sharedList | sharedItinerary`.
enum SharedContentPreview {
  static func place() -> Loci_Share_SharedContent {
    var c = Loci_Share_SharedContent()
    c.metadata.contentType = .restaurant
    c.restaurant.id = "7d1d9a2e-6b4f-4c1b-9d3e-1a2b3c4d5e6f"
    c.restaurant.name = "Tasca do Chico"
    c.restaurant.address = "Rua do Diário de Notícias 39, Lisbon"
    c.restaurant.cuisineType = "Portuguese"
    c.restaurant.rating = 4.6
    return c
  }

  static func list() -> Loci_Share_SharedContent {
    var c = Loci_Share_SharedContent()
    c.metadata.contentType = .list
    c.list.id = "l-1"
    c.list.name = "Lisbon cafés"
    c.list.description_p = "Where the pastel de nata is still warm."
    c.list.itemCount = 8
    return c
  }

  static func itinerary() -> Loci_Share_SharedContent {
    var c = Loci_Share_SharedContent()
    c.metadata.contentType = .itinerary
    c.itinerary.id = "i-1"
    c.itinerary.title = "Porto weekend"
    c.itinerary.cityName = "Porto"
    c.itinerary.durationDays = 2
    c.itinerary.stopCount = 9
    return c
  }

  static func view(_ content: Loci_Share_SharedContent) -> some View {
    NavigationStack { SharedContentView(code: "preview", load: { _ in content }).appRouteDestinations() }
  }
}
