import Foundation
import LociConnectProto
import Testing

@testable import loci

struct TripDayActivityTests {
  @Test func liveActivityTextIsSharedWithTheWidget() {
    var state = TripDayAttributes.ContentState(
      phase: .atStop, currentIndex: 1, currentName: "Pantheon", slotEnd: Date(), nextName: "Piazza Navona", nextDistanceMeters: 1234, stopsDone: 1
    )
    #expect(state.nextText == "Next: Piazza Navona · 1.2 km")
    #expect(state.progressText(of: 5) == "1/5")
    state.nextDistanceMeters = 40
    #expect(state.nextText == "Next: Piazza Navona · 40 m")
    state.nextDistanceMeters = nil
    #expect(state.nextText == "Next: Piazza Navona")
    state.nextName = nil
    #expect(state.nextText == nil)
  }

  private func slot(_ i: Int, _ name: String, start: Date, minutes: Int, next: Double? = nil) -> TimelineSlot {
    var stop = Loci_Trip_TripStop()
    stop.id = name
    stop.name = name
    return TimelineSlot(
      stop: stop, index: i, start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)), coordinate: nil, distanceToNextMeters: next
    )
  }

  @Test func stateFollowsTheScheduleAndTheManualOverride() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let slots = [
      slot(0, "A", start: t0.addingTimeInterval(600), minutes: 60, next: 500), slot(1, "B", start: t0.addingTimeInterval(4500), minutes: 60),
    ]
    let before = TripDayActivityController.state(slots: slots, manualIndex: nil, startedAt: t0, now: t0)
    #expect(before.0.phase == .beforeFirst && before.0.currentName == "A" && !before.shouldEnd)
    let during = TripDayActivityController.state(slots: slots, manualIndex: nil, startedAt: t0, now: t0.addingTimeInterval(1200))
    #expect(during.0.phase == .atStop && during.0.currentIndex == 0 && during.0.nextName == "B" && during.0.nextDistanceMeters == 500)
    let between = TripDayActivityController.state(slots: slots, manualIndex: nil, startedAt: t0, now: t0.addingTimeInterval(4300))
    #expect(between.0.phase == .between && between.0.stopsDone == 1)
    let manual = TripDayActivityController.state(slots: slots, manualIndex: 1, startedAt: t0, now: t0.addingTimeInterval(1200))
    #expect(manual.0.currentIndex == 1 && manual.0.phase == .atStop)
  }

  @Test func endsAfterTheLastSlotOrTwelveHours() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let slots = [slot(0, "A", start: t0, minutes: 60)]
    #expect(!TripDayActivityController.state(slots: slots, manualIndex: nil, startedAt: t0, now: t0.addingTimeInterval(80 * 60)).shouldEnd)
    let late = TripDayActivityController.state(slots: slots, manualIndex: nil, startedAt: t0, now: t0.addingTimeInterval(91 * 60))
    #expect(late.shouldEnd && late.0.phase == .done)
    let longDay = [slot(0, "A", start: t0, minutes: 240), slot(1, "B", start: t0.addingTimeInterval(13 * 3600), minutes: 60)]
    #expect(TripDayActivityController.state(slots: longDay, manualIndex: nil, startedAt: t0, now: t0.addingTimeInterval(12 * 3600 + 1)).shouldEnd)
  }

  @Test func stopsWithoutCoordinatesStillRunOnTheSchedule() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let slots = [slot(0, "A", start: t0, minutes: 60), slot(1, "B", start: t0.addingTimeInterval(4500), minutes: 60)]
    let state = TripDayActivityController.state(slots: slots, manualIndex: nil, startedAt: t0, now: t0.addingTimeInterval(60)).0
    #expect(state.phase == .atStop && state.nextName == "B" && state.nextDistanceMeters == nil)
    #expect(TripDayActivityController.fenceable(slots).isEmpty)
  }
}
