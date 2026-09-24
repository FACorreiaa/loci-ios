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
}
