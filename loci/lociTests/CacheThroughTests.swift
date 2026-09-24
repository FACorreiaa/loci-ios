import Foundation
import LociConnectProto
import Testing

@testable import loci

struct CacheThroughTests {
  private func cache() -> LocalCache {
    LocalCache(root: FileManager.default.temporaryDirectory.appending(path: "loci-ct-\(UUID().uuidString)"))
  }

  private func trip(_ title: String) -> Loci_Trip_TripDraft {
    var t = Loci_Trip_TripDraft()
    t.id = "t1"
    t.title = title
    return t
  }

  @Test func freshFetchOverwritesTheCopy() async throws {
    let cache = cache()
    try await cache.put(trip("old"), kind: .trip, id: "t1")
    let loaded = await cacheThrough(Loci_Trip_TripDraft.self, kind: .trip, id: "t1", cache: cache) { trip("new") }
    guard case .fresh(let value) = loaded else {
      Issue.record("expected fresh")
      return
    }
    #expect(value.title == "new")
    #expect(try #require(await cache.get(Loci_Trip_TripDraft.self, kind: .trip, id: "t1")).value.title == "new")
  }

  @MainActor @Test func networkErrorKeepsTheCopyAsStale() async throws {
    let cache = cache()
    try await cache.put(trip("copy"), kind: .trip, id: "t1")
    var handedCopy: String?
    let loaded = await cacheThrough(Loci_Trip_TripDraft.self, kind: .trip, id: "t1", cache: cache, onCached: { handedCopy = $0.value.title }) {
      throw APIError.network("offline")
    }
    #expect(handedCopy == "copy")
    guard case let .stale(value, _, reason) = loaded else {
      Issue.record("expected stale")
      return
    }
    #expect(value.title == "copy")
    #expect(loaded.isOffline)
    if case .network = reason {} else { Issue.record("reason should be the network error") }
  }

  @Test func expiredTokenWithACopyIsStaleNotMissing() async throws {
    let cache = cache()
    try await cache.put(trip("copy"), kind: .trip, id: "t1")
    let loaded = await cacheThrough(Loci_Trip_TripDraft.self, kind: .trip, id: "t1", cache: cache) { throw APIError.unauthorized(nil) }
    #expect(loaded.value?.title == "copy")
    #expect(!loaded.isOffline)
  }

  @Test func noCopyAndAnErrorIsMissing() async {
    let loaded = await cacheThrough(Loci_Trip_TripDraft.self, kind: .trip, id: "t1", cache: cache()) { throw APIError.network("offline") }
    guard case .missing = loaded else {
      Issue.record("expected missing")
      return
    }
    #expect(loaded.value == nil)
  }

  @Test func chipWordingFollowsTheState() {
    let now = Date()
    let twoHoursAgo = now.addingTimeInterval(-7200)
    #expect(CacheChipText.text(staleSince: nil, isOffline: false, now: now) == nil)
    #expect(CacheChipText.text(staleSince: twoHoursAgo, isOffline: false, now: now) == "Saved 2 hours ago")
    #expect(CacheChipText.text(staleSince: twoHoursAgo, isOffline: true, now: now) == "Offline · last updated 2 hours ago")
  }
}
