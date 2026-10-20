import Foundation
import LociConnectProto
import Testing

@testable import loci

nonisolated private func response() -> Loci_Place_ImportPlacesResponse {
  var res = Loci_Place_ImportPlacesResponse()
  res.source = .tiktok
  res.sourceTitle = "3 bakeries in Lisbon"
  res.cityName = "Lisbon"
  var a = Loci_Place_ImportedPlace()
  a.name = "Manteigaria"
  a.cityName = "Lisbon"
  a.note = "best nata"
  a.poiID = "p1"
  a.address = "R. do Loreto 2"
  var b = Loci_Place_ImportedPlace()
  b.name = "Ghost Café"
  b.cityName = "Lisbon"
  var c = Loci_Place_ImportedPlace()
  c.name = "Aloma"
  c.cityName = "Lisbon"
  c.poiID = "p3"
  res.places = [a, b, c]
  return res
}

nonisolated final class StubLinkImportService: LinkImportService, @unchecked Sendable {
  var result = LinkImportResult(response())
  var importError: Error?
  var addErrors: [String: Error] = [:]
  var calls: [String] = []
  var hints: [String] = []

  func importPlaces(url: String, cityHint: String) async throws -> LinkImportResult {
    calls.append("import:\(url)")
    hints.append(cityHint)
    if let importError { throw importError }
    return result
  }

  func createList(name: String) async throws -> String {
    calls.append("create:\(name)")
    return "L1"
  }

  func addPlace(poiID: String, toList listID: String) async throws {
    calls.append("add:\(listID):\(poiID)")
    if let error = addErrors[poiID] { throw error }
  }
}

struct LinkImportResultTests {
  @Test func keepsEveryPlaceAndPicksTheSaveableOnes() {
    let result = LinkImportResult(response())
    #expect(result.source == "TikTok")
    #expect(result.places.map(\.name) == ["Manteigaria", "Ghost Café", "Aloma"])
    #expect(result.places.map(\.canSave) == [true, false, true])
    #expect(result.places[0].address == "R. do Loreto 2")
    #expect(result.defaultSelection == [result.places[0].id, result.places[2].id])
    #expect(Set(result.places.map(\.id)).count == 3)
  }

  @Test func listNameComesFromTheTitleThenTheCity() {
    #expect(LinkImportResult(response()).defaultListName == "3 bakeries in Lisbon")
    var long = response()
    long.sourceTitle = String(repeating: "x", count: 200)
    #expect(LinkImportResult(long).defaultListName.count == 60)
    var untitled = response()
    untitled.sourceTitle = ""
    #expect(LinkImportResult(untitled).defaultListName == "Places in Lisbon")
    untitled.cityName = ""
    #expect(LinkImportResult(untitled).defaultListName == "Imported places")
  }

  @Test func pastedLinksAreTidiedOrRefused() {
    #expect(LinkImportLink.normalized("  https://vm.tiktok.com/ZMabc/ ") == "https://vm.tiktok.com/ZMabc/")
    #expect(LinkImportLink.normalized("maps.app.goo.gl/AbC") == "https://maps.app.goo.gl/AbC")
    #expect(LinkImportLink.normalized("Watch this! https://youtu.be/xyz") == "https://youtu.be/xyz")
    #expect(LinkImportLink.normalized("not a link") == nil)
    #expect(LinkImportLink.normalized("ftp://example.com/a") == nil)
  }
}

@MainActor struct LinkImportStoreTests {
  @Test func readingPicksTheSaveablePlaces() async {
    let service = StubLinkImportService()
    let store = LinkImportStore(service: service)
    store.url = "https://vm.tiktok.com/ZMabc/"
    store.cityHint = " Lisbon "
    await store.read()
    #expect(service.hints == ["Lisbon"])
    #expect(store.result?.places.count == 3)
    #expect(store.chosen.map(\.name) == ["Manteigaria", "Aloma"])
    #expect(store.listName == "3 bakeries in Lisbon")
  }

  @Test func aPlaceNotFoundCannotBePicked() async throws {
    let store = LinkImportStore(service: StubLinkImportService())
    store.url = "https://vm.tiktok.com/ZMabc/"
    await store.read()
    let places = try #require(store.result).places
    let ghost = places[1]
    store.toggle(ghost)
    #expect(!store.isPicked(ghost))
    store.toggle(places[0])
    #expect(store.chosen.map(\.name) == ["Aloma"])
  }

  @Test func aBadLinkNeverReachesTheServer() async {
    let service = StubLinkImportService()
    let store = LinkImportStore(service: service)
    store.url = "hello"
    await store.read()
    #expect(service.calls.isEmpty)
    #expect(store.error?.contains("public link") == true)
  }

  @Test func savesIntoANewListInOrder() async {
    let service = StubLinkImportService()
    let store = LinkImportStore(service: service)
    store.url = "https://vm.tiktok.com/ZMabc/"
    await store.read()
    store.listName = "Bakeries"
    await store.save()
    #expect(service.calls.dropFirst() == ["create:Bakeries", "add:L1:p1", "add:L1:p3"])
    #expect(store.outcome == LinkImportOutcome(listID: "L1", added: 2, already: 0, failed: 0))
  }

  @Test func alreadyThereCountsAndAFailureKeepsThePlacePicked() async {
    let service = StubLinkImportService()
    service.addErrors = ["p1": APIError.conflict("exists"), "p3": APIError.network("offline")]
    let store = LinkImportStore(service: service)
    store.url = "https://vm.tiktok.com/ZMabc/"
    await store.read()
    store.target = .existing("L9")
    await store.save()
    #expect(store.outcome == LinkImportOutcome(listID: "L9", added: 0, already: 1, failed: 1))
    // Only the one that failed stays picked, ready to try again.
    #expect(store.chosen.map(\.name) == ["Aloma"])
    #expect(!service.calls.contains { $0.hasPrefix("create:") })
  }

  @Test func serverRefusalsReadAsSentences() async {
    let service = StubLinkImportService()
    service.importError = APIError.custom("no places found on that page")
    let store = LinkImportStore(service: service)
    store.url = "https://example.com/post"
    await store.read()
    #expect(store.error == "No places found on that page.")
    #expect(store.result == nil)
  }
}
