import Foundation
import LociConnectProto
import Testing

@testable import loci

@MainActor
struct AskLociControllerTests {
  private func make(_ service: FakeAskLociService) -> (AskLociController, FakeSpeaker) {
    let speaker = FakeSpeaker()
    let controller = AskLociController(
      service: service,
      speaker: speaker,
      context: {
        var context = Loci_Assistant_ClientContext()
        context.screen = "test"
        return context
      }
    )
    return (controller, speaker)
  }

  @Test("a typed question shows the answer and stays silent")
  func typedIsSilent() async {
    let (controller, speaker) = make(FakeAskLociService([.text("It rains. "), .done(reason: .complete)]))
    controller.ask("  Weather?  ", voice: false)
    await controller.waitForAnswer()
    #expect(controller.turns.map(\.you) == ["Weather?"])
    #expect(controller.turns[0].reply == "It rains. ")
    #expect(!controller.asking)
    #expect(speaker.said.isEmpty)
  }

  @Test("a spoken question is answered aloud, sentence by sentence")
  func voiceSpeaks() async {
    let service = FakeAskLociService([.text("It rains. Bring"), .text(" a coat."), .done(reason: .complete)])
    let (controller, speaker) = make(service)
    controller.ask("Weather?", voice: true)
    await controller.waitForAnswer()
    #expect(speaker.said == ["It rains.", "Bring a coat."])
    #expect(service.requests.first?.inputMode == .voice)
  }

  @Test("the speaker toggle reads typed answers too")
  func toggleSpeaks() async {
    let (controller, speaker) = make(FakeAskLociService([.text("Yes."), .done(reason: .complete)]))
    controller.speakTyped = true
    controller.ask("Open?", voice: false)
    await controller.waitForAnswer()
    #expect(speaker.said == ["Yes."])
  }

  @Test("blank text asks nothing")
  func blank() {
    let (controller, _) = make(FakeAskLociService([]))
    controller.ask("   \n", voice: false)
    #expect(controller.turns.isEmpty)
    #expect(!controller.asking)
  }

  @Test("the conversation carries to the next question")
  func conversationCarries() async {
    let service = FakeAskLociService([.done(reason: .complete, conversation: "c1")])
    let (controller, _) = make(service)
    controller.ask("One", voice: false)
    await controller.waitForAnswer()
    controller.ask("Two", voice: false)
    await controller.waitForAnswer()
    #expect(service.requests.map(\.hasConversationID) == [false, true])
    #expect(service.requests.last?.conversationID == "c1")
  }

  @Test("a stream that ends without Done says the connection dropped")
  func noDone() async {
    let (controller, _) = make(FakeAskLociService([.text("Partial")]))
    controller.ask("Hi", voice: false)
    await controller.waitForAnswer()
    #expect(controller.turns[0].reply == "Partial")
    #expect(controller.turns[0].failure == "The connection dropped.")
  }

  @Test(
    "a failure is worded for the person, and only 'switched off' offers the chat",
    arguments: [
      (AskLociFailure.unavailable, "Ask Loci isn't available yet. The chat still is.", true),
      (.signedOut, "Sign in again to ask.", false),
      (.unreachable, "I couldn't reach Loci. Try again.", false),
    ]
  )
  func failures(failure: AskLociFailure, message: String, offersChat: Bool) async {
    let (controller, _) = make(FakeAskLociService([], fail: failure))
    controller.ask("Hi", voice: false)
    await controller.waitForAnswer()
    #expect(controller.turns[0].failure == message)
    #expect(controller.turns[0].offerChat == offersChat)
    #expect(!controller.asking)
  }

  @Test("stop keeps what arrived, ends the voice and settles the turn")
  func stopKeeps() async {
    let service = FakeAskLociService([.text("First. ")], hang: true)
    let (controller, speaker) = make(service)
    controller.ask("Hi", voice: true)
    await service.waitUntilHanging()
    await Task.yield()
    controller.stop()
    await controller.waitForAnswer()
    #expect(controller.turns[0].done)
    #expect(!controller.asking)
    #expect(speaker.stops >= 1)
  }

  @Test("a new question stops the one before it")
  func newStopsOld() async {
    let service = FakeAskLociService([], hang: true)
    let (controller, _) = make(service)
    controller.ask("One", voice: false)
    await service.waitUntilHanging()
    service.hang = false
    controller.ask("Two", voice: false)
    await controller.waitForAnswer()
    #expect(controller.turns.count == 2)
    #expect(controller.turns[0].done)
    #expect(controller.turns[0].failure == nil)
  }

  @Test("nothing is confirmed until the person taps, and a confirmed card becomes its note")
  func confirm() async {
    let service = FakeAskLociService([.place(id: "p1"), .done(reason: .complete)])
    let (controller, _) = make(service)
    controller.ask("Save it", voice: false)
    await controller.waitForAnswer()
    #expect(service.confirmed.isEmpty)
    let before = controller.changes

    await controller.confirm(card: "p1", turn: controller.turns[0].id)
    #expect(service.confirmed == ["p1"])
    #expect(controller.turns[0].cards == [.note(id: "p1", text: "Saved it.")])
    #expect(controller.changes == before + 1)
  }

  @Test("a card that fails stays, with the reason")
  func confirmFails() async {
    let service = FakeAskLociService([.place(id: "p1"), .done(reason: .complete)])
    service.confirmError = TripActionError(kind: .gone, message: "")
    let (controller, _) = make(service)
    controller.ask("Save it", voice: false)
    await controller.waitForAnswer()
    await controller.confirm(card: "p1", turn: controller.turns[0].id)
    #expect(controller.turns[0].cards.map(\.id) == ["p1"])
    #expect(controller.state(ofCard: "p1") == .failed("This suggestion was already used or has expired."))
    #expect(controller.changes == 0)
  }

  @Test("Not now removes the card and tells the server, even if the server is unreachable")
  func dismiss() async {
    let service = FakeAskLociService([.place(id: "p1"), .done(reason: .complete)])
    service.dismissError = TripActionError(kind: .other, message: "")
    let (controller, _) = make(service)
    controller.ask("Save it", voice: false)
    await controller.waitForAnswer()
    await controller.dismiss(card: "p1", turn: controller.turns[0].id)
    #expect(controller.turns[0].cards.isEmpty)
    #expect(service.dismissed == ["p1"])
  }

  @Test("closing ends the answer; reopening carries on with the conversation")
  func closeAndReopen() async {
    let service = FakeAskLociService([.done(reason: .complete, conversation: "c1")])
    let (controller, speaker) = make(service)
    controller.open(listen: false)
    controller.ask("One", voice: false)
    await controller.waitForAnswer()
    controller.close()
    #expect(!controller.isOpen)
    #expect(speaker.stops >= 1)
    controller.open(listen: false)
    #expect(controller.turns.count == 1)
  }

  @Test("a new account starts with nothing of the old one")
  func resetForgets() async {
    let service = FakeAskLociService([.done(reason: .complete, conversation: "c1")])
    let (controller, _) = make(service)
    controller.open(listen: false)
    controller.speakTyped = true
    controller.ask("One", voice: false)
    await controller.waitForAnswer()
    controller.reset()
    #expect(controller.turns.isEmpty)
    #expect(!controller.isOpen)
    #expect(!controller.speakTyped)
    controller.ask("Two", voice: false)
    await controller.waitForAnswer()
    #expect(service.requests.last?.hasConversationID == false)
  }
}

// MARK: - Fakes

@MainActor
private final class FakeSpeaker: AskLociSpeaking {
  var said: [String] = []
  var stops = 0

  func say(_ text: String) { said.append(text) }
  func stop() { stops += 1 }
}

private final class FakeAskLociService: AskLociService, @unchecked Sendable {
  private let lock = NSLock()
  private let events: [Loci_Assistant_AssistantEvent]
  private let fail: AskLociFailure?
  private var _hang: Bool
  private var _requests: [Loci_Assistant_AskAssistantRequest] = []
  private var _confirmed: [String] = []
  private var _dismissed: [String] = []
  private var _confirmError: TripActionError?
  private var _dismissError: TripActionError?

  init(_ events: [Loci_Assistant_AssistantEvent], fail: AskLociFailure? = nil, hang: Bool = false) {
    self.events = events
    self.fail = fail
    _hang = hang
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  var hang: Bool {
    get { locked { _hang } }
    set { locked { _hang = newValue } }
  }

  var requests: [Loci_Assistant_AskAssistantRequest] { locked { _requests } }
  var confirmed: [String] { locked { _confirmed } }
  var dismissed: [String] { locked { _dismissed } }
  var confirmError: TripActionError? {
    get { locked { _confirmError } }
    set { locked { _confirmError = newValue } }
  }
  var dismissError: TripActionError? {
    get { locked { _dismissError } }
    set { locked { _dismissError = newValue } }
  }

  func waitUntilHanging() async {
    while requests.isEmpty { await Task.yield() }
  }

  func ask(_ request: Loci_Assistant_AskAssistantRequest) -> AsyncThrowingStream<Loci_Assistant_AssistantEvent, Error> {
    locked { _requests.append(request) }
    let (events, fail, hang) = (events, fail, hang)
    return AsyncThrowingStream { continuation in
      for event in events { continuation.yield(event) }
      if let fail {
        continuation.finish(throwing: fail)
      } else if !hang {
        continuation.finish()
      }
    }
  }

  func confirm(proposalID: String, option: Int?) async throws(TripActionError) -> Loci_Assistant_ConfirmActionResponse {
    locked { _confirmed.append(proposalID) }
    if let confirmError { throw confirmError }
    var response = Loci_Assistant_ConfirmActionResponse()
    response.confirmation = "Saved it."
    return response
  }

  func dismiss(proposalID: String) async throws(TripActionError) {
    locked { _dismissed.append(proposalID) }
    if let dismissError { throw dismissError }
  }
}

extension Loci_Assistant_AssistantEvent {
  static func text(_ text: String) -> Self {
    var delta = Loci_Assistant_TextDelta()
    delta.text = text
    var event = Self()
    event.event = .textDelta(delta)
    return event
  }

  static func status(_ label: String) -> Self {
    var status = Loci_Assistant_ToolStatus()
    status.label = label
    var event = Self()
    event.event = .toolStatus(status)
    return event
  }

  static func place(id: String) -> Self {
    var place = Loci_Assistant_PlaceAction()
    place.id = id
    var proposal = Loci_Assistant_Proposal()
    proposal.kind = .place(place)
    var event = Self()
    event.event = .proposal(proposal)
    return event
  }

  static func handoff(_ query: String) -> Self {
    var handoff = Loci_Assistant_Handoff()
    handoff.query = query
    var event = Self()
    event.event = .handoff(handoff)
    return event
  }

  static func done(
    reason: Loci_Assistant_DoneReason,
    degraded: Bool = false,
    conversation: String = ""
  ) -> Self {
    var done = Loci_Assistant_Done()
    done.reason = reason
    done.degraded = degraded
    done.conversationID = conversation
    var event = Self()
    event.event = .done(done)
    return event
  }
}
