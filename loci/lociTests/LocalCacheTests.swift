import Foundation
import LociConnectProto
import Testing

@testable import loci

struct LocalCacheTests {
  private func temporaryCache() -> LocalCache {
    LocalCache(root: FileManager.default.temporaryDirectory.appending(path: "loci-cache-\(UUID().uuidString)"))
  }

  @Test func roundTripsAProtoWithItsFetchTime() async throws {
    let cache = temporaryCache()
    var trip = Loci_Trip_TripDraft()
    trip.id = "t1"
    trip.title = "Rome on foot"
    try await cache.put(trip, kind: .trip, id: "t1")
    let cached = try #require(await cache.get(Loci_Trip_TripDraft.self, kind: .trip, id: "t1"))
    #expect(cached.value.title == "Rome on foot")
    #expect(abs(cached.fetchedAt.timeIntervalSinceNow) < 5)
    #expect(await cache.ids(kind: .trip) == ["t1"])
  }

  @Test func missingAndRemovedEntriesReadAsNil() async throws {
    let cache = temporaryCache()
    #expect(await cache.get(Loci_Trip_TripDraft.self, kind: .trip, id: "nope") == nil)
    try await cache.put(Loci_Trip_TripDraft(), kind: .trip, id: "t2")
    await cache.remove(kind: .trip, id: "t2")
    #expect(await cache.get(Loci_Trip_TripDraft.self, kind: .trip, id: "t2") == nil)
    #expect(await cache.ids(kind: .trip).isEmpty)
  }

  @Test func clearEmptiesEveryKind() async throws {
    let cache = temporaryCache()
    try await cache.put(Loci_Trip_TripDraft(), kind: .trip, id: "a")
    try await cache.put(Loci_Localcontext_LocalContext(), kind: .localContext, id: LocalCache.key(latitude: 41.9028, longitude: 12.4964))
    await cache.clear()
    #expect(await cache.ids(kind: .trip).isEmpty)
    #expect(await cache.ids(kind: .localContext).isEmpty)
  }

  @Test func coordinateKeyRoundsToThreeDecimals() {
    #expect(LocalCache.key(latitude: 41.90284, longitude: 12.49637) == "41.903,12.496")
  }
}
