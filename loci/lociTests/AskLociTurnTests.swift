import Foundation
import LociConnectProto
import Testing

@testable import loci

struct SentenceChunkerTests {
  @Test("a sentence is spoken as soon as it ends")
  func completeSentence() {
    var chunker = SentenceChunker()
    #expect(chunker.push("Porto is lovely. It r").elementsEqual(["Porto is lovely."]))
    #expect(chunker.push("ains.").isEmpty)
    #expect(chunker.flush() == ["It rains."])
    #expect(chunker.flush().isEmpty)
  }

  @Test(
    "a full stop that doesn't end a sentence waits",
    arguments: ["It has 3.5 stars ", "Ask J. Smith ", "Walk to St. George ", "See Dr. Silva "]
  )
  func notAnEnd(text: String) {
    var chunker = SentenceChunker()
    #expect(chunker.push(text).isEmpty)
  }

  @Test("newlines end a piece, and closing quotes stay with their sentence")
  func newlinesAndQuotes() {
    var chunker = SentenceChunker()
    #expect(chunker.push("First line\nHe said \"go.\" Then") == ["First line", "He said \"go.\""])
  }

  @Test("text with no ending is cut at a space before it gets too long")
  func longTextCut() {
    var chunker = SentenceChunker()
    let pieces = chunker.push(String(repeating: "word ", count: 100))
    #expect(!pieces.isEmpty)
    #expect(pieces.allSatisfy { $0.count <= SentenceChunker.maxPending })
    #expect((pieces + chunker.flush()).joined(separator: " ").split(separator: " ").count == 100)
  }

  @Test("markdown and links don't reach the voice")
  func speakable() {
    #expect(SentenceChunker.speakable("**Try** [Time Out](https://x.y/z) `now`") == "Try Time Out now")
    #expect(SentenceChunker.speakable("See https://x.y/z today") == "See today")
  }

  @Test("a piece that is only punctuation is dropped")
  func onlyPunctuation() {
    var chunker = SentenceChunker()
    #expect(chunker.push("***\n").isEmpty)
  }
}

struct SilenceDetectorTests {
  /// The answers for a run of (power, time) readings.
  private func feed(_ readings: [(Float, TimeInterval)]) -> [Bool] {
    var detector = SilenceDetector()
    return readings.map { detector.feed(power: $0.0, at: $0.1) }
  }

  @Test("a pause before the first word never stops the recording")
  func silenceBeforeSpeech() {
    #expect(feed([(-60, 0), (-60, 30)]) == [false, false])
  }

  @Test("stops once the pause after speech is long enough")
  func stopsAfterSpeech() {
    #expect(feed([(-20, 1), (-60, 2), (-60, 1 + SilenceDetector.silenceAfter)]) == [false, false, true])
  }

  @Test("speaking again restarts the wait")
  func speakingAgain() {
    #expect(feed([(-20, 1), (-20, 2), (-60, 2.5)]) == [false, false, false])
  }
}

@MainActor
struct AppContextStoreTests {
  private let tripID = "6f9619ff-8b86-4d01-b42d-00cf4fc964ff"
  private let listID = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
  private let placeID = "550e8400-e29b-41d4-a716-446655440000"

  @Test("with nothing on show, the selected tab names the screen")
  func fallsBackToTab() {
    let store = AppContextStore()
    #expect(store.current(tab: .calendar).screen == "calendar")
    #expect(store.current(tab: .assistant).screen == "chat")
    #expect(store.current(tab: .calendar).entities.isEmpty)
  }

  @Test("the newest screen wins, and leaving it restores the one beneath")
  func newestWins() {
    let store = AppContextStore()
    let (list, trip) = (UUID(), UUID())
    store.show(AskLociScreen(screen: "list_detail", lists: [listID]), token: list)
    store.show(AskLociScreen(screen: "trip_detail", trips: [tripID]), token: trip)
    #expect(store.current(tab: .saved).screen == "trip_detail")
    #expect(store.current(tab: .saved).entities.map(\.id) == [tripID])
    #expect(store.current(tab: .saved).entities.map(\.type) == [.trip])
    store.hide(token: trip)
    #expect(store.current(tab: .saved).screen == "list_detail")
    store.hide(token: list)
    #expect(store.current(tab: .saved).screen == "saved")
  }

  @Test("a screen whose data changed updates in place")
  func updatesInPlace() {
    let store = AppContextStore()
    let token = UUID()
    store.show(AskLociScreen(screen: "place_detail"), token: token)
    store.show(AskLociScreen(screen: "place_detail", places: [placeID]), token: token)
    #expect(store.current(tab: .saved).entities.map(\.id) == [placeID])
    store.hide(token: token)
    #expect(store.current(tab: .saved).screen == "saved")
  }

  @Test("only a stored id is sent", arguments: ["", "name:majestic-cafe", "abc"])
  func onlyStoredIDs(id: String) {
    #expect(AskLociScreen(screen: "x", trips: [id]).entities.isEmpty)
  }
}

struct AskLociTurnTests {
  @Test("text clears the status, and Done settles the turn")
  func textAndDone() {
    var turn = AskLociTurn(id: 1, you: "Hi")
    turn.apply(.status("Checking your trips"))
    #expect(turn.status == "Checking your trips")
    turn.apply(.text("Hel"))
    turn.apply(.text("lo"))
    #expect(turn.reply == "Hello")
    #expect(turn.status == nil)
    turn.apply(.done(reason: .complete))
    #expect(turn.done)
    #expect(turn.closingNote == nil)
  }

  @Test(
    "the reason decides the closing note",
    arguments: [
      (Loci_Assistant_DoneReason.interrupted, "That answer stopped part way."),
      (.dailyLimit, "That's all the questions for today. Ask again tomorrow."),
      (.refused, "I can't help with that one."),
      (.unavailable, "I can't answer right now. Try again in a moment."),
    ]
  )
  func closingNotes(reason: Loci_Assistant_DoneReason, note: String) {
    var turn = AskLociTurn(id: 1, you: "Hi")
    turn.apply(.done(reason: reason))
    #expect(turn.closingNote == note)
  }

  @Test("an answer without tools says it can't change anything")
  func degraded() {
    var turn = AskLociTurn(id: 1, you: "Hi")
    turn.apply(.done(reason: .complete, degraded: true))
    #expect(turn.closingNote == "I can't check your details or change anything right now.")
  }

  @Test("a card becomes its note, or goes if there is none")
  func settle() {
    var turn = AskLociTurn(id: 1, you: "Save it")
    turn.apply(.place(id: "a"))
    turn.apply(.place(id: "b"))
    turn.apply(.handoff("Plan Porto"))
    #expect(turn.cards.map(\.id) == ["a", "b", "handoff-2"])
    turn.settleCard("a", note: "Saved.")
    turn.settleCard("b", note: nil)
    #expect(turn.cards.count == 2)
    #expect(turn.cards.first == .note(id: "a", text: "Saved."))
  }

  @Test("the planner's prompt names the city once")
  func prompt() {
    #expect(plannerPrompt(query: "3 days of food", city: "Porto") == "3 days of food in Porto")
    #expect(plannerPrompt(query: "3 days in porto", city: "Porto") == "3 days in porto")
    #expect(plannerPrompt(query: "3 days", city: nil) == "3 days")
    #expect(plannerPrompt(query: "3 days", city: "") == "3 days")
  }
}
