import Foundation
import LociConnectProto
import Testing

@testable import loci

/// The Muse header's status copy and avatar mood (muse-chat-contract.md, "Avatar states + status copy").
@MainActor struct MuseActivityTests {
  @Test func noSearchIsReady() {
    #expect(MuseActivity.resolve(status: nil) == MuseActivity(mood: .idle, status: "Ready"))
    #expect(MuseActivity.resolve(status: .idle) == .ready)
    #expect(MuseActivity.resolve(nil as SearchState?) == .ready)
  }

  @Test func streamingBeforeTextIsThinking() {
    #expect(MuseActivity.resolve(status: .streaming) == MuseActivity(mood: .working, status: "is thinking"))
  }

  @Test func streamingWithTextIsWriting() {
    #expect(MuseActivity.resolve(status: .streaming, hasText: true) == MuseActivity(mood: .working, status: "is writing"))
  }

  @Test func placesLandingCountAsWriting() {
    var state = SearchState()
    state.status = .streaming
    state.destination = .hotels
    state.apply(Events.hotels(["Memmo Alfama"], id: "e1"))
    #expect(MuseActivity.resolve(state).status == "is writing")
  }

  @Test func knownStageWinsOverThinkingAndWriting() {
    #expect(MuseActivity.resolve(status: .streaming, progressStage: "finding places").status == "is finding places")
    #expect(MuseActivity.resolve(status: .streaming, hasText: true, progressStage: "Checking hours").status == "is checking hours")
  }

  @Test func detachedSaysYouCanLeave() {
    let activity = MuseActivity.resolve(status: .detached, hasText: true, progressStage: "finding places")
    #expect(activity == MuseActivity(mood: .working, status: "is still working — you can leave"))
  }

  @Test func workingWinsOverTheComposer() {
    #expect(MuseActivity.resolve(status: .streaming, isListening: true).mood == .working)
  }

  @Test func composerFocusIsListening() {
    #expect(MuseActivity.resolve(status: .completed, isListening: true) == MuseActivity(mood: .listening, status: "is listening"))
    #expect(MuseActivity.resolve(status: nil, isListening: true).status == "is listening")
  }

  @Test func finishedWithoutAFlashIsReady() {
    #expect(MuseActivity.resolve(status: .completed) == .ready)
    #expect(MuseActivity.resolve(status: .failed("x")) == .ready)
  }

  @Test func celebratingNamesThePlaces() {
    #expect(MuseActivity.resolve(status: .completed, flash: .celebrating(places: 7)) == MuseActivity(mood: .celebrating, status: "found 7 places"))
    #expect(MuseActivity.resolve(status: .completed, flash: .celebrating(places: 1)).status == "found 1 place")
    #expect(MuseActivity.resolve(status: .completed, flash: .celebrating(places: 0)).status == "is done")
  }

  @Test func snagIsIdleArt() {
    #expect(MuseActivity.resolve(status: .failed("boom"), flash: .snag) == MuseActivity(mood: .idle, status: "hit a snag"))
  }

  @Test func flashOutranksTheComposer() {
    #expect(MuseActivity.resolve(status: .completed, flash: .snag, isListening: true).status == "hit a snag")
  }

  // MARK: - Flashes

  @Test func finishingARunningSearchCelebrates() {
    #expect(MuseActivity.flash(from: .streaming, to: .completed, places: 3) == .celebrating(places: 3))
    #expect(MuseActivity.flash(from: .detached, to: .completed, places: 0) == .celebrating(places: 0))
  }

  @Test func failingARunningSearchIsASnag() {
    #expect(MuseActivity.flash(from: .streaming, to: .failed("The search failed."), places: 0) == .snag)
    #expect(MuseActivity.flash(from: .detached, to: .failed("This search didn't finish."), places: 0) == .snag)
  }

  @Test func stopIsNotASnag() {
    #expect(MuseActivity.flash(from: .streaming, to: .failed(SearchState.stoppedMessage), places: 0) == nil)
  }

  @Test func openingAFinishedSearchEarnsNothing() {
    #expect(MuseActivity.flash(from: nil, to: .completed, places: 4) == nil)
    #expect(MuseActivity.flash(from: .idle, to: .completed, places: 4) == nil)
    #expect(MuseActivity.flash(from: .completed, to: .failed("x"), places: 0) == nil)
    #expect(MuseActivity.flash(from: .streaming, to: .detached, places: 0) == nil)
  }

  @Test func celebrationLastsOnePointTwoSeconds() {
    #expect(MuseActivity.Flash.celebrating(places: 1).duration == .milliseconds(1200))
  }

  // MARK: - Stage strings

  @Test func stagePhraseTakesHumanStrings() {
    #expect(MuseActivity.stagePhrase("finding places") == "finding places")
    #expect(MuseActivity.stagePhrase("  Checking opening hours… ") == "checking opening hours")
    #expect(MuseActivity.stagePhrase("is reading reviews") == "reading reviews")
    #expect(MuseActivity.stagePhrase("Is mapping the route...") == "mapping the route")
    #expect(MuseActivity.stagePhrase("POI lookup") == "POI lookup")
  }

  @Test func stagePhraseDropsMachineNamesAndBlanks() {
    #expect(MuseActivity.stagePhrase(nil) == nil)
    #expect(MuseActivity.stagePhrase("") == nil)
    #expect(MuseActivity.stagePhrase("   ") == nil)
    #expect(MuseActivity.stagePhrase("...") == nil)
    #expect(MuseActivity.stagePhrase("progress") == nil)
    #expect(MuseActivity.stagePhrase("intent_classified") == nil)
    #expect(MuseActivity.resolve(status: .streaming, progressStage: "semantic_context_generated").status == "is thinking")
  }

  @Test func stagePhraseCutsAt32Characters() throws {
    let long = "checking opening hours and the tram timetable for every stop"
    let phrase = try #require(MuseActivity.stagePhrase(long))
    #expect(phrase.count <= MuseActivity.maxStageLength)
    #expect(phrase == "checking opening hours and the…")
    #expect(phrase.hasSuffix("…"))
    #expect(phrase.hasPrefix("checking opening hours"))
    let exact = String(repeating: "a", count: 32)
    #expect(MuseActivity.stagePhrase(exact) == exact)
  }

  // MARK: - Reduced from the stream

  @Test func streamWalksThroughThinkingStageWritingAndDone() {
    var state = SearchState()
    state.status = .streaming
    state.apply(Events.start("s1", domain: .itinerary, city: "Lisbon"))
    #expect(MuseActivity.resolve(state).status == "is thinking")

    var progress = Loci_Chat_StreamEvent()
    progress.eventID = "e1"
    progress.progress.stage = "finding places"
    state.apply(progress)
    #expect(MuseActivity.resolve(state).status == "is finding places")

    state.apply(Events.token("Belém first", id: "e2"))
    #expect(MuseActivity.resolve(state).status == "is writing")

    var complete = Loci_Chat_StreamEvent()
    complete.eventID = "e3"
    complete.complete.sessionID = "s1"
    let old = state.status
    state.apply(complete)
    let flash = MuseActivity.flash(from: old, to: state.status, places: state.places.count)
    #expect(MuseActivity.resolve(state, flash: flash).mood == .celebrating)
    #expect(MuseActivity.resolve(state).status == "Ready")
  }
}
