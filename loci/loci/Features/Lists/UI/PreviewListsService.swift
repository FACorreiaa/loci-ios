import Foundation
import LociConnectProto
import SwiftUI

/// Offline sample data for `-designPreview lists`, `listDetail` and
/// `addToList`, and for the tests. Writes succeed and change nothing, except
/// that `limitAfter` lists makes the next create fail as the free plan would.
nonisolated struct PreviewListsService: ListsService {
  var limitAfter: Int?

  func lists() async throws -> [LociList] { LociList.previewLists }

  func list(id: String) async throws -> ListDetail {
    let list = LociList.previewLists.first { $0.id == id } ?? LociList.previewLists[0]
    return ListDetail(list: list, entries: ListEntry.previewLisbon)
  }

  func create(_ form: ListForm, cityId: String?) async throws -> LociList {
    if let limitAfter, LociList.previewLists.count >= limitAfter { throw EntitlementLimit(feature: .lists) }
    return LociList(id: UUID().uuidString, name: form.trimmedName, description: form.trimmedDescription, createdAt: Date())
  }

  func update(_ listId: String, form: ListForm) async throws -> LociList {
    LociList(id: listId, name: form.trimmedName, description: form.trimmedDescription, isPublic: form.isPublic)
  }

  func delete(_ listId: String) async throws {}
  func add(_ stop: Loci_Poi_POIDetailedInfo, destination: SearchDestination, to listId: String) async throws {}
  func remove(_ entry: ListEntry, from listId: String) async throws {}
}

extension ListDetailStore {
  static var preview: ListDetailStore {
    let list = LociList.previewLists[0]
    return ListDetailStore(listID: list.id, initial: list, service: PreviewListsService())
  }
}

extension AddToListStore {
  static var preview: AddToListStore { AddToListStore(stop: ListEntry.previewStop, destination: .activities, service: PreviewListsService()) }
}

nonisolated extension LociList {
  static var previewLists: [LociList] {
    let day: TimeInterval = 86_400
    return [
      LociList(
        id: "9b1f0c2e-0000-4000-8000-000000000001",
        name: "Lisbon, slowly",
        description: "Viewpoints and long lunches for the next visit",
        isPublic: true,
        createdAt: Date().addingTimeInterval(-2 * day)
      ),
      LociList(
        id: "9b1f0c2e-0000-4000-8000-000000000002",
        name: "Porto weekend",
        description: "Two days along the river",
        isItinerary: true,
        createdAt: Date().addingTimeInterval(-9 * day)
      ),
      LociList(id: "9b1f0c2e-0000-4000-8000-000000000003", name: "Rainy-day museums", createdAt: Date().addingTimeInterval(-30 * day)),
      LociList(
        id: "9b1f0c2e-0000-4000-8000-000000000004",
        name: "Where to eat in Alfama",
        description: "Tascas a friend swears by",
        createdAt: Date().addingTimeInterval(-41 * day)
      ),
    ]
  }
}

nonisolated extension ListEntry {
  static var previewLisbon: [ListEntry] {
    func place(
      _ id: String,
      _ name: String,
      _ category: String,
      _ blurb: String,
      _ lat: Double?,
      _ lon: Double?,
      rating: Double,
      _ type: Loci_List_ContentType = .poi,
      photo: String? = nil
    ) -> ListEntry {
      var stop = Loci_Poi_POIDetailedInfo()
      stop.id = id
      stop.name = name
      stop.category = category
      stop.description_p = blurb
      stop.city = "Lisbon"
      stop.rating = rating
      if let lat, let lon {
        stop.latitude = lat
        stop.longitude = lon
      }
      if let photo {
        var credit = Loci_Poi_POIImage()
        credit.url = photo
        credit.attribution = "Wikimedia Commons"
        stop.imageCredits = [credit]
      }
      return ListEntry(itemID: id, contentType: type, stop: stop)
    }
    return [
      place(
        "5c7e0000-0000-4000-8000-000000000001",
        "Miradouro da Senhora do Monte",
        "Viewpoint",
        "The highest lookout in the city; go at sunset.",
        38.7193,
        -9.1325,
        rating: 4.8,
        photo: "https://upload.wikimedia.org/wikipedia/commons/thumb/9/9f/Miradouro_da_Senhora_do_Monte_%2838530147244%29.jpg/330px-Miradouro_da_Senhora_do_Monte_%2838530147244%29.jpg"
      ),
      place(
        "5c7e0000-0000-4000-8000-000000000002",
        "Taberna da Rua das Flores",
        "Restaurant",
        "Small plates, a short menu on a chalkboard, no bookings.",
        38.7107,
        -9.1432,
        rating: 4.6,
        .restaurant,
        photo: "https://upload.wikimedia.org/wikipedia/commons/thumb/3/39/Bacalhau_a_Bras.jpg/330px-Bacalhau_a_Bras.jpg"
      ),
      place(
        "5c7e0000-0000-4000-8000-000000000003",
        "Museu Nacional do Azulejo",
        "Museum",
        "Five centuries of tiles in a former convent.",
        38.7247,
        -9.1136,
        rating: 4.7,
        photo: "https://upload.wikimedia.org/wikipedia/commons/thumb/6/64/Access_stairs_to_small_cloister_%28Claustrim%29%2C_Museu_Nacional_do_Azulejo%2C_Lisbon%2C_Portugal_julesvernex2.jpg/330px-Access_stairs_to_small_cloister_%28Claustrim%29%2C_Museu_Nacional_do_Azulejo%2C_Lisbon%2C_Portugal_julesvernex2.jpg"
      ),
      place(
        "5c7e0000-0000-4000-8000-000000000004",
        "Feira da Ladra",
        "Market",
        "The flea market behind São Vicente.",
        nil,
        nil,
        rating: 4.3,
        photo: "https://upload.wikimedia.org/wikipedia/commons/thumb/0/0a/Feira_da_Ladra%2C_Lisboa%2C_Jul_2024.jpg/330px-Feira_da_Ladra%2C_Lisboa%2C_Jul_2024.jpg"
      ),
    ]
  }

  static var previewStop: Loci_Poi_POIDetailedInfo { previewLisbon[0].stop }
}

/// `-designPreview addToList`: a place's detail with the sheet open over it.
struct AddToListPreview: View {
  var body: some View { NavigationStack { detail }.sheet(isPresented: .constant(true), content: sheet) }

  private var detail: some View { PlaceDetailView(stop: ListEntry.previewStop, destination: .activities, cityName: "Lisbon") }

  private func sheet() -> some View { AddToListSheet(store: .preview) }
}
