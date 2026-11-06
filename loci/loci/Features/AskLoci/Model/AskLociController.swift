import AVFoundation
import CoreLocation
import LociConnectProto
import Observation

/// The assistant you can ask from anywhere. It owns its own stream and never
/// touches `SearchSessionController`, so nothing here can disturb a running search.
/// Only `confirm` can change anything, and only because the person tapped.
@MainActor @Observable
final class AskLociController {
  static let shared = AskLociController()

  private(set) var isOpen = false
  private(set) var turns: [AskLociTurn] = []
  private(set) var asking = false
  private(set) var cardStates: [String: TripActionsModel.CardState] = [:]
  /// Read typed answers aloud too. Spoken questions always get a spoken answer.
  var speakTyped = false {
    didSet { if !speakTyped { speaker.stop() } }
  }
  /// Bumped when a card changed something, so a page on show can reload.
  private(set) var changes = 0

  let dictation: DictationController

  @ObservationIgnored private let service: AskLociService
  @ObservationIgnored private let speaker: AskLociSpeaking
  /// Tests supply the context; the app reads it from where the person is.
  @ObservationIgnored private let contextOverride: (@MainActor () -> Loci_Assistant_ClientContext)?
  @ObservationIgnored private var conversationID: String?
  @ObservationIgnored private var inflight: Task<Void, Never>?
  @ObservationIgnored private var nextID = 1
  @ObservationIgnored private var coordinate: CLLocationCoordinate2D?

  init(
    service: AskLociService = ConnectAskLociService(),
    speaker: AskLociSpeaking = AskLociSpeaker(),
    dictation: DictationController = DictationController(stopsOnSilence: true),
    context: (@MainActor () -> Loci_Assistant_ClientContext)? = nil
  ) {
    self.service = service
    self.speaker = speaker
    self.dictation = dictation
    self.contextOverride = context
  }

  /// What the mic is doing.
  var micState: DictationController.State { previewMic ?? dictation.state }

  @ObservationIgnored private var previewMic: DictationController.State?

  /// For `-designPreview` screens: open, with this conversation already in it.
  func preview(turns: [AskLociTurn], mic: DictationController.State? = nil) {
    self.turns = turns
    // A question asked on the preview must not reuse a sample turn's id.
    nextID = (turns.map(\.id).max() ?? 0) + 1
    previewMic = mic
    isOpen = true
  }

  // MARK: - Opening

  /// `listen` is true for a hold on the tab: the mic starts straight away if
  /// the app already may use it. A first-time prompt waits for a tap on the mic,
  /// so nobody meets a permission dialog they didn't ask for.
  func open(listen: Bool) {
    guard !isOpen else { return }
    isOpen = true
    refreshLocation()
    if listen, AVAudioApplication.shared.recordPermission == .granted {
      Task { await toggleMic() }
    }
  }

  /// Closing ends the answer and the voice. The conversation stays, so reopening
  /// carries on where it was.
  func close() {
    guard isOpen else { return }
    isOpen = false
    dictation.cancel()
    stop()
  }

  /// The account changed: nothing of this conversation may survive it.
  func reset() {
    close()
    turns = []
    cardStates = [:]
    conversationID = nil
    speakTyped = false
  }

  /// In the background only the voice stops; the answer keeps arriving.
  func didEnterBackground() {
    dictation.cancel()
    speaker.stop()
  }

  // MARK: - Asking

  func toggleMic() async {
    if dictation.state == .idle {
      stop()
    }
    guard let text = await dictation.toggle(), isOpen else { return }
    ask(text, voice: true)
  }

  func ask(_ text: String, voice: Bool) {
    let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty else { return }
    stop()

    let id = nextID
    nextID += 1
    turns.append(AskLociTurn(id: id, you: question))
    asking = true

    let request = makeRequest(question, voice: voice)
    let aloud = voice || speakTyped
    inflight = Task { [weak self] in
      await self?.run(request, turn: id, aloud: aloud)
    }
  }

  /// Stops the answer and the voice. What has arrived stays on screen.
  func stop() {
    inflight?.cancel()
    inflight = nil
    speaker.stop()
    asking = false
    for index in turns.indices where !turns[index].done {
      turns[index].done = true
      turns[index].status = nil
    }
  }

  /// Runs to the end of an answer; for tests that want to await it.
  func waitForAnswer() async { await inflight?.value }

  private func run(_ request: Loci_Assistant_AskAssistantRequest, turn id: Int, aloud: Bool) async {
    var chunker = SentenceChunker()
    let speak = { [speaker] (pieces: [String]) in
      guard aloud else { return }
      for piece in pieces { speaker.say(piece) }
    }
    do {
      for try await event in service.ask(request) {
        guard !Task.isCancelled else { return }
        if case let .textDelta(delta) = event.event { speak(chunker.push(delta.text)) }
        if case let .done(done) = event.event, !done.conversationID.isEmpty {
          conversationID = done.conversationID
        }
        update(id) { $0.apply(event) }
      }
      guard !Task.isCancelled else { return }
      speak(chunker.flush())
      // A stream that ends without a Done lost its connection part way.
      update(id) { turn in
        if !turn.done {
          turn.done = true
          turn.status = nil
          turn.failure = "The connection dropped."
        }
      }
    } catch {
      guard !Task.isCancelled, !(error is CancellationError) else { return }
      let failure = error as? AskLociFailure ?? .unreachable
      update(id) { turn in
        turn.done = true
        turn.status = nil
        turn.failure = failure.message
        turn.offerChat = failure == .unavailable
      }
    }
    asking = false
    inflight = nil
  }

  private func update(_ id: Int, _ change: (inout AskLociTurn) -> Void) {
    guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
    change(&turns[index])
  }

  // MARK: - Cards

  func state(ofCard id: String) -> TripActionsModel.CardState { cardStates[id] ?? .ready }

  func confirm(card id: String, turn turnID: Int, option: Int? = nil) async {
    guard state(ofCard: id) != .applying else { return }
    cardStates[id] = .applying
    do {
      let response = try await service.confirm(proposalID: id, option: option)
      cardStates[id] = .applied
      changes += 1
      update(turnID) { $0.settleCard(id, note: response.confirmation.isEmpty ? "Done." : response.confirmation) }
    } catch {
      cardStates[id] = .failed(error.userMessage)
    }
  }

  func dismiss(card id: String, turn turnID: Int) async {
    guard state(ofCard: id) != .applying else { return }
    cardStates[id] = .dismissed
    update(turnID) { $0.settleCard(id, note: nil) }
    try? await service.dismiss(proposalID: id)  // a courtesy to the server; the card goes either way
  }

  /// A handoff has nothing on the server to dismiss.
  func dropHandoff(card id: String, turn turnID: Int) {
    update(turnID) { $0.settleCard(id, note: nil) }
  }

  // MARK: - Context

  private func makeRequest(_ text: String, voice: Bool) -> Loci_Assistant_AskAssistantRequest {
    var request = Loci_Assistant_AskAssistantRequest()
    if let conversationID { request.conversationID = conversationID }
    request.text = text
    request.inputMode = voice ? .voice : .typed
    request.context = contextOverride?() ?? liveContext()
    return request
  }

  private func liveContext() -> Loci_Assistant_ClientContext {
    let screen = AppContextStore.shared.current(tab: AppRouter.shared.selectedTab)
    var context = Loci_Assistant_ClientContext()
    context.surface = .ios
    context.screen = screen.screen
    context.entities = screen.entities
    if let city = screen.city, !city.isEmpty { context.city = city }
    // No default location: a guessed one reads as a confident answer about the
    // wrong city.
    if let coordinate {
      context.latitude = coordinate.latitude
      context.longitude = coordinate.longitude
    }
    context.locale = Locale.current.identifier
    context.timezone = TimeZone.current.identifier
    return context
  }

  /// Never asks for permission: the assistant is no reason to meet that dialog.
  private func refreshLocation() {
    let manager = CLLocationManager()
    switch manager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways: break
    default:
      coordinate = nil
      return
    }
    if let last = manager.location, last.timestamp.timeIntervalSinceNow > -900 {
      coordinate = last.coordinate
    }
    Task { [weak self] in
      if let fresh = try? await CurrentLocation.fetch(timeout: .seconds(3)) { self?.coordinate = fresh }
    }
  }
}
