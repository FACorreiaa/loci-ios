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
}
