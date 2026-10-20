import Foundation
import LociConnectProto
import Testing
import UserNotifications

@testable import loci

@MainActor struct RatePrompterTests {
  private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
  }

  private static func defaults() -> UserDefaults {
    let name = "rate-prompter-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  private static func pending(_ id: String, at date: Date, due: TimeInterval = RatePrompter.followUp) -> PendingRating {
    PendingRating(poiID: id, name: id, cityName: "Lisbon", category: "", arrivedAt: date, dueAt: date.addingTimeInterval(due))
  }

  @Test func promptIsNotDueBeforeDueAt() {
    let clock = Clock()
    let prompter = RatePrompter(defaults: Self.defaults(), live: false) { clock.now }
    prompter.enqueue(Self.pending("a", at: clock.now))
    #expect(prompter.current == nil)
    clock.now = clock.now.addingTimeInterval(RatePrompter.followUp + 1)
    prompter.refresh()
    #expect(prompter.current?.poiID == "a")
  }

  @Test func markDueSurfacesImmediately() {
    let clock = Clock()
    let prompter = RatePrompter(defaults: Self.defaults(), live: false) { clock.now }
    prompter.enqueue(Self.pending("a", at: clock.now))
    prompter.markDue(poiID: "a")
    #expect(prompter.current?.poiID == "a")
    prompter.resolve(poiID: "a")
    #expect(prompter.current == nil)
    #expect(prompter.queue.isEmpty)
  }

  @Test func enqueueDedupesAndCapsAtTen() {
    let clock = Clock()
    let prompter = RatePrompter(defaults: Self.defaults(), live: false) { clock.now }
    for i in 0..<12 {
      prompter.enqueue(Self.pending("p\(i)", at: clock.now.addingTimeInterval(Double(i))))
    }
    prompter.enqueue(Self.pending("p11", at: clock.now.addingTimeInterval(20)))
    #expect(prompter.queue.count == RatePrompter.capacity)
    #expect(Set(prompter.queue.map(\.poiID)).count == RatePrompter.capacity)
    #expect(!prompter.queue.contains { $0.poiID == "p0" })
  }

  @Test func staleEntriesDropAfterThreeDays() {
    let clock = Clock()
    let prompter = RatePrompter(defaults: Self.defaults(), live: false) { clock.now }
    prompter.enqueue(Self.pending("old", at: clock.now))
    clock.now = clock.now.addingTimeInterval(RatePrompter.maxAge + 1)
    prompter.refresh()
    #expect(prompter.queue.isEmpty)
  }

  @Test func queueSurvivesReload() {
    let clock = Clock()
    let defaults = Self.defaults()
    let first = RatePrompter(defaults: defaults, live: false) { clock.now }
    first.enqueue(Self.pending("a", at: clock.now, due: 0))
    let second = RatePrompter(defaults: defaults, live: false) { clock.now }
    #expect(second.current?.poiID == "a")
  }

  @Test func arrivalWithoutAPlaceIDIsNotQueued() {
    let clock = Clock()
    let prompter = RatePrompter(defaults: Self.defaults(), live: false) { clock.now }
    prompter.enqueueArrival(poiID: "not-a-uuid", name: "X", cityName: "Lisbon", category: "")
    prompter.enqueueArrival(poiID: UUID().uuidString, name: "Y", cityName: " ", category: "")
    #expect(prompter.queue.isEmpty)
    prompter.enqueueArrival(poiID: UUID().uuidString, name: "Z", cityName: "Lisbon", category: "cafe")
    #expect(prompter.queue.count == 1)
    #expect(prompter.current == nil)
  }

  private struct StubRanking: RankingService {
    var next: Loci_Ranking_Comparison?
    var fails = false

    func rate(_ pending: PendingRating, verdict: RankingVerdict) async throws -> RankingStep {
      if fails { throw URLError(.notConnectedToInternet) }
      var place = Loci_Ranking_RankedPlace()
      place.poiID = pending.poiID
      return RankingStep(place: place, next: next)
    }

    func compare(poiID: String, otherID: String, better: Bool) async throws -> RankingStep {
      RankingStep(place: Loci_Ranking_RankedPlace(), next: nil)
    }

    func mine(city: String) async throws -> [Loci_Ranking_RankedPlace] { [] }
    func user(id: String, city: String) async throws -> [Loci_Ranking_RankedPlace] { [] }
  }

  @Test func notificationVerdictResolvesWhenPlaced() async {
    let clock = Clock()
    let prompter = RatePrompter(defaults: Self.defaults(), live: false) { clock.now }
    prompter.enqueue(Self.pending("a", at: clock.now))
    await RateReminder.handle(actionIdentifier: RankingVerdict.loved.actionIdentifier, poiID: "a", prompter: prompter, service: StubRanking())
    #expect(prompter.queue.isEmpty)
  }

  /// Comparisons can't be asked on the lock screen: the place stays queued and
  /// due, so the card picks them up when the app opens.
  @Test func notificationVerdictKeepsEntryWhenComparisonsRemain() async {
    let clock = Clock()
    let prompter = RatePrompter(defaults: Self.defaults(), live: false) { clock.now }
    prompter.enqueue(Self.pending("a", at: clock.now))
    var other = Loci_Ranking_Comparison()
    other.poiID = "b"
    await RateReminder.handle(actionIdentifier: RankingVerdict.loved.actionIdentifier, poiID: "a", prompter: prompter, service: StubRanking(next: other))
    #expect(prompter.current?.poiID == "a")
  }

  /// Offline, or suspended mid-call: the answer is not lost.
  @Test func notificationVerdictFailureKeepsEntry() async {
    let clock = Clock()
    let prompter = RatePrompter(defaults: Self.defaults(), live: false) { clock.now }
    prompter.enqueue(Self.pending("a", at: clock.now))
    await RateReminder.handle(actionIdentifier: RankingVerdict.fine.actionIdentifier, poiID: "a", prompter: prompter, service: StubRanking(fails: true))
    #expect(prompter.current?.poiID == "a")
  }
}
