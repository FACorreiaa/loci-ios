import Connect
import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Lists (parity pass 2, Phase 2): the request each ListService RPC gets, the
/// free-plan refusal (web's entitlement-error.ts), and the tab filter.
struct ListPayloadTests {
  private let listID = "9b1f0c2e-0000-4000-8000-000000000001"
  private let poiID = "5c7e0000-0000-4000-8000-000000000001"
  private let cityID = "c1770000-0000-4000-8000-000000000001"
  private let nilUUID = "00000000-0000-0000-0000-000000000000"

  private func stop(id: String) -> Loci_Poi_POIDetailedInfo {
    var stop = Loci_Poi_POIDetailedInfo()
    stop.id = id
    stop.name = "Miradouro da Graça"
    stop.description_p = "A lookout."
    return stop
  }

  @Test func getListsAsksForWebsPage() {
    let request = ListPayload.getLists(userId: "u1")
    #expect(request.userID == "u1")
    #expect(request.limit == 100)
    #expect(request.offset == 0)
    #expect(!request.includeItems)
  }

  @Test func getListAsksForDetailedItems() {
    let request = ListPayload.getList(userId: "u1", listId: listID)
    #expect(request.listID == listID)
    #expect(request.includeDetailedItems)
  }

  @Test func createTrimsAndCarriesEveryToggle() {
    let form = ListForm(name: "  Porto  ", description: " Two days \n", isItinerary: true, isPublic: true)
    let request = ListPayload.create(userId: "u1", form: form)
    #expect(request.userID == "u1")
    #expect(request.name == "Porto")
    #expect(request.description_p == "Two days")
    #expect(request.isItinerary)
    #expect(request.isPublic)
    #expect(request.cityID.isEmpty)
  }

  @Test func createSendsOnlyARealCityID() {
    let form = ListForm(name: "Porto")
    #expect(ListPayload.create(userId: "u1", form: form, cityId: cityID).cityID == cityID)
    #expect(ListPayload.create(userId: "u1", form: form, cityId: nilUUID).cityID.isEmpty)
    #expect(ListPayload.create(userId: "u1", form: form, cityId: "Lisbon").cityID.isEmpty)
  }

  @Test func updateSendsNamePublicAndDescription() {
    let form = ListForm(name: " Lisbon ", description: "Slowly", isItinerary: true, isPublic: true)
    let request = ListPayload.update(userId: "u1", listId: listID, form: form)
    #expect(request.listID == listID)
    #expect(request.name == "Lisbon")
    #expect(request.description_p == "Slowly")
    #expect(request.isPublic)
  }

  @Test func deleteNamesTheList() {
    let request = ListPayload.delete(userId: "u1", listId: listID)
    #expect(request.userID == "u1")
    #expect(request.listID == listID)
  }

  @Test func addItemKeysOnThePOIAndTheDomain() throws {
    let request = try #require(ListPayload.addItem(userId: "u1", listId: listID, stop: stop(id: poiID), destination: .restaurants))
    #expect(request.listID == listID)
    #expect(request.itemID == poiID)
    #expect(request.contentType == .restaurant)
    #expect(request.position == 0)
    #expect(request.notes.isEmpty)
    #expect(request.itemAiDescription == "A lookout.")
    #expect(!request.hasRecommendationTrace)
  }

  @Test func addItemPassesTheRecommendationTrace() throws {
    var place = stop(id: poiID)
    var trace = Loci_Recommendation_RecommendationTrace()
    trace.runID = "run-1"
    place.recommendationTrace = trace
    let request = try #require(ListPayload.addItem(userId: "u1", listId: listID, stop: place, destination: .activities))
    #expect(request.hasRecommendationTrace)
    #expect(request.recommendationTrace.runID == "run-1")
  }

  @Test func addItemRefusesANameKeyedPlace() {
    #expect(ListPayload.addItem(userId: "u1", listId: listID, stop: stop(id: ""), destination: .activities) == nil)
    #expect(ListPayload.addItem(userId: "u1", listId: listID, stop: stop(id: "Graça|38.7|-9.1"), destination: .activities) == nil)
    #expect(!ListPayload.canAdd(stop(id: nilUUID)))
    #expect(ListPayload.canAdd(stop(id: poiID)))
  }

  @Test func addItemCapsTheDescription() throws {
    var place = stop(id: poiID)
    place.description_p = String(repeating: "a", count: 5000)
    let request = try #require(ListPayload.addItem(userId: "u1", listId: listID, stop: place, destination: .activities))
    #expect(request.itemAiDescription.count == ListPayload.maxDescription)
  }

  @Test func removeItemCarriesTheRowsKind() {
    let entry = ListEntry(itemID: poiID, contentType: .hotel, stop: stop(id: poiID))
    let request = ListPayload.removeItem(userId: "u1", listId: listID, entry: entry)
    #expect(request.itemID == poiID)
    #expect(request.contentType == .hotel)
  }

  @Test func contentTypeFollowsTheDomain() {
    #expect(ListPayload.contentType(for: .hotels) == .hotel)
    #expect(ListPayload.contentType(for: .restaurants) == .restaurant)
    #expect(ListPayload.contentType(for: .activities) == .poi)
    #expect(ListPayload.contentType(for: .itinerary) == .poi)
    #expect(ListPayload.destination(for: .hotel) == .hotels)
    #expect(ListPayload.destination(for: .unspecified) == .activities)
    #expect(ListPayload.analyticsName(.restaurant) == "restaurant")
    #expect(ListPayload.analyticsName(.unspecified) == "poi")
  }

  @Test func quickListIsNamedForThePlace() {
    let form = ListForm.quick(name: " Views ", for: "Miradouro da Graça")
    #expect(form.trimmedName == "Views")
    #expect(form.description == "List created for Miradouro da Graça")
    #expect(!form.isItinerary)
    #expect(!form.isPublic)
    #expect(!ListForm.quick(name: "   ", for: "x").isValid)
  }

  @Test func formStartsFromTheList() {
    let list = LociList(id: listID, name: "Porto", description: "River", isPublic: true, isItinerary: true)
    #expect(ListForm(list) == ListForm(name: "Porto", description: "River", isItinerary: true, isPublic: true))
  }

  @Test func listFromProtoDropsTheNilCity() {
    var proto = Loci_List_List()
    proto.id = listID
    proto.name = "Porto"
    proto.cityID = nilUUID
    #expect(LociList(proto).cityID == nil)
    proto.cityID = cityID
    #expect(LociList(proto).cityID == cityID)
  }

  @Test func entryLooksUpByPOIIDWhenThereIsOne() {
    var item = Loci_List_ListItem()
    item.itemID = "item-1"
    item.poiID = nilUUID
    #expect(ListEntry.lookupID(item) == "item-1")
    item.poiID = poiID
    #expect(ListEntry.lookupID(item) == poiID)
    item.itemAiDescription = "Kept blurb"
    let entry = ListEntry(item)
    #expect(entry.stop.name == ListEntry.unnamed)
    #expect(entry.stop.description_p == "Kept blurb")
  }
}

/// Ported from web's classifyEntitlementError.
struct EntitlementLimitTests {
  @Test func headerNamesTheFeature() {
    #expect(EntitlementLimit.classify(code: .permissionDenied, headers: ["x-loci-entitlement": ["lists"]], message: nil)?.feature == .lists)
    #expect(EntitlementLimit.classify(code: .permissionDenied, headers: ["X-Loci-Entitlement": [" Places "]], message: "")?.feature == .places)
  }

  @Test func messageIsTheFallback() {
    #expect(EntitlementLimit.classify(code: .permissionDenied, headers: [:], message: "free lists limit reached (5)")?.feature == .lists)
    #expect(EntitlementLimit.classify(code: .permissionDenied, headers: [:], message: "Places limit: 50")?.feature == .places)
    #expect(EntitlementLimit.classify(code: .permissionDenied, headers: [:], message: "Upgrade to keep going")?.feature == .places)
  }

  @Test func anUnknownHeaderFallsThroughToTheMessage() {
    let limit = EntitlementLimit.classify(code: .permissionDenied, headers: ["x-loci-entitlement": ["export"]], message: "list limit")
    #expect(limit?.feature == .lists)
  }

  @Test func onlyPermissionDeniedCounts() {
    #expect(EntitlementLimit.classify(code: .resourceExhausted, headers: ["x-loci-entitlement": ["lists"]], message: "lists limit") == nil)
    #expect(EntitlementLimit.classify(code: nil, headers: [:], message: "lists limit") == nil)
    #expect(EntitlementLimit.classify(code: .permissionDenied, headers: [:], message: "access denied to list") == nil)
  }

  @Test func copyIsWebsWithoutAPurchasePitch() {
    #expect(EntitlementLimit(feature: .lists).message == "Free plans include 5 lists.")
    #expect(EntitlementLimit(feature: .places).message == "Free plans include 50 saved places.")
    for feature in [EntitlementLimit.Feature.lists, .places] {
      let limit = EntitlementLimit(feature: feature)
      #expect(!limit.suggestion.localizedCaseInsensitiveContains("upgrade"))
      #expect(!limit.suggestion.localizedCaseInsensitiveContains("pricing"))
    }
  }
}

struct ListFilterTests {
  private let lists = [
    LociList(id: "a", name: "Lisbon"),
    LociList(id: "b", name: "Porto weekend", isItinerary: true),
    LociList(id: "c", name: "Museums"),
  ]

  @Test func tabsSplitCustomFromItineraries() {
    #expect(ListFilter.apply(lists, tab: .all).map(\.id) == ["a", "b", "c"])
    #expect(ListFilter.apply(lists, tab: .custom).map(\.id) == ["a", "c"])
    #expect(ListFilter.apply(lists, tab: .itineraries).map(\.id) == ["b"])
  }

  @Test func countsPerTab() {
    let counts = ListFilter.counts(lists)
    #expect(counts[.all] == 3)
    #expect(counts[.custom] == 2)
    #expect(counts[.itineraries] == 1)
    #expect(ListFilter.counts([])[.all] == 0)
  }
}

@MainActor struct ListsStoreTests {
  @Test func aRefusedCreateOpensTheLimitAndKeepsTheSheet() async {
    let store = ListsStore(service: PreviewListsService(limitAfter: 0))
    await store.load()
    let closed = await store.save(ListForm(name: "One more"), editing: nil)
    #expect(!closed)
    #expect(store.limit == EntitlementLimit(feature: .lists))
    #expect(store.error == nil)
    #expect(store.lists.count == LociList.previewLists.count)
  }

  @Test func createPutsTheListFirst() async {
    let store = ListsStore(service: PreviewListsService())
    await store.load()
    #expect(await store.save(ListForm(name: " New "), editing: nil))
    #expect(store.lists.first?.name == "New")
  }

  @Test func tabFiltersWhatIsVisible() async {
    let store = ListsStore(service: PreviewListsService())
    await store.load()
    store.tab = .itineraries
    let allItineraries = store.visible.allSatisfy { $0.isItinerary }
    #expect(allItineraries)
    #expect(!store.visible.isEmpty)
  }

  @Test func deleteTakesTheRowOut() async {
    let store = ListsStore(service: PreviewListsService())
    await store.load()
    let first = store.lists[0]
    await store.delete(first)
    #expect(!store.lists.contains(first))
  }

  @Test func addToANewListCreatesItFirst() async {
    let store = AddToListStore(stop: ListEntry.previewStop, destination: .activities, service: PreviewListsService())
    await store.load()
    #expect(await store.createAndAdd(name: "Views"))
    #expect(store.lists.first?.name == "Views")
    #expect(store.lists.first?.description == "List created for Miradouro da Senhora do Monte")
  }
}
