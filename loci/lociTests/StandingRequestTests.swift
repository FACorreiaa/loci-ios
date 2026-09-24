import Connect
import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

// Muse chat stage C: proactive messages and the standing-task card
// (muse-chat-contract.md, "Proactive messages" and "Standing-task card").

// MARK: - Heuristic

struct StandingRequestTests {
  @Test(arguments: [
    "Every morning at 8, tell me if it'll rain in Lisbon",
    "remind me to book the Alhambra tickets",
    "Let me know when the Sagrada Família has late openings",
    "keep an eye on ferry strikes in Naples",
    "Notify me if the Uffizi releases Friday night tickets",
    "each Monday send me three new restaurants in Porto",
    "check daily whether the Lisbon trams are running",
    "Every 3 hours update me on the Etna eruption",
    "Ping me when cherry blossom forecasts for Kyoto come out",
    "Every week, brief me on events in Berlin",
  ])
  func standingRequestsMatch(_ text: String) {
    #expect(StandingRequest.matches(text))
  }

  @Test(arguments: [
    "3 days in Lisbon with kids, nothing too hilly",
    "3 days in Rome, gelato every day",
    "Show me a plan with a museum every day",
    "Tell me when the Louvre opens on Sunday",
    "What's the weather like in Porto in March?",
    "Where should we eat tonight in Trastevere?",
    "",
  ])
  func oneOffQuestionsDoNot(_ text: String) {
    #expect(!StandingRequest.matches(text))
  }

  @Test func caseAndSpacingDoNotMatter() {
    #expect(StandingRequest.matches("EVERY   MORNING tell   me the forecast"))
    #expect(StandingRequest.matches("Keep\nan eye on Lisbon strikes"))
  }
}

// MARK: - Mapping

struct MuseMessageMappingTests {
  private func stored(
    _ id: String,
    role: Loci_Chat_MessageRole = .assistant,
    origin: Loci_Chat_MessageOrigin,
    label: String = "",
    content: String = "Hello",
    at seconds: TimeInterval = 0
  ) -> Loci_Chat_ConversationMessage {
    var message = Loci_Chat_ConversationMessage()
    message.id = id
    message.role = role
    message.content = content
    message.origin = origin
    message.sourceLabel = label
    message.timestamp = .init(date: Date(timeIntervalSince1970: seconds))
    return message
  }

  @Test func unspecifiedReadsAsReply() {
    let message = MuseMessage(stored("a", origin: .unspecified, label: "Standing task"))
    #expect(message.origin == .reply)
    #expect(message.caption == nil)
  }

  @Test func unknownOriginReadsAsReply() {
    #expect(MuseMessage(stored("a", origin: .UNRECOGNIZED(9))).origin == .reply)
  }

  @Test func proactiveCarriesItsLabel() {
    let message = MuseMessage(stored("a", origin: .proactive, label: " Briefing · 07:00 "))
    #expect(message.origin == .proactive)
    #expect(message.role == .agent)
    #expect(message.caption == "Briefing · 07:00")
  }

  @Test func proactiveWithoutALabelStillHasACaption() {
    #expect(MuseMessage(stored("a", origin: .proactive)).caption == MuseMessage.fallbackCaption)
  }

  @Test func userRoleMapsToUser() {
    #expect(MuseMessage(stored("a", role: .user, origin: .reply)).role == .user)
  }

  @Test func threadKeepsOnlyTheAgentsOwnMessagesOldestFirst() {
    let history = [
      stored("reply", origin: .reply),
      stored("late", origin: .proactive, label: "Standing task", at: 200),
      stored("user", role: .user, origin: .proactive),
      stored("early", origin: .proactive, label: "Standing task", at: 100),
      stored("legacy", origin: .unspecified),
    ]
    #expect(MuseMessage.proactive(in: history).map(\.id) == ["early", "late"])
  }

  @Test func errorCodesMapToFriendlyCases() {
    #expect(WatchError(code: .invalidArgument) == .notUnderstood)
    #expect(WatchError(code: .notFound) == .notFound)
    #expect(WatchError(code: .resourceExhausted) == .tooMany)
    #expect(WatchError(code: .unauthenticated) == .signedOut)
    #expect(WatchError(code: .unavailable) == .offline)
    #expect(WatchError(code: .internalError) == .other)
    #expect(WatchError.tooMany.errorDescription?.contains("10 standing tasks") == true)
    #expect(WatchError.notUnderstood.errorDescription?.contains("every morning") == true)
  }
}

// MARK: - Card flows

/// Records calls and answers from canned results.
actor StubStandingTaskService: StandingTaskService {
  enum Call: Equatable {
    case propose(String, String)
    case create(String, String)
    case list(String?)
    case delete(String)
    case history(String)
  }

  private(set) var calls: [Call] = []
  var proposeResult: Result<Loci_Chat_WatchProposal, WatchError> = .success(.preview)
  var createResult: Result<Loci_Chat_CreateWatchResponse, WatchError> = .success(StubStandingTaskService.created())
  var listResult: Result<[Loci_Chat_Watch], WatchError> = .success([])
  var deleteError: WatchError?
  var historyResult: [Loci_Chat_ConversationMessage] = []

  init(
    propose: Result<Loci_Chat_WatchProposal, WatchError> = .success(.preview),
    create: Result<Loci_Chat_CreateWatchResponse, WatchError> = .success(StubStandingTaskService.created()),
    list: Result<[Loci_Chat_Watch], WatchError> = .success([]),
    deleteError: WatchError? = nil,
    history: [Loci_Chat_ConversationMessage] = []
  ) {
    proposeResult = propose
    createResult = create
    listResult = list
    self.deleteError = deleteError
    historyResult = history
  }

  static func created(id: String = "w-1") -> Loci_Chat_CreateWatchResponse {
    var response = Loci_Chat_CreateWatchResponse()
    response.watch.id = id
    response.confirmation.id = "confirm-\(id)"
    response.confirmation.role = .assistant
    response.confirmation.content = "Got it — I'll watch the Lisbon forecast and ping you when rain is likely."
    response.confirmation.origin = .proactive
    response.confirmation.sourceLabel = "Standing task"
    return response
  }

  func propose(text: String, timezone: String) async throws(WatchError) -> Loci_Chat_WatchProposal {
    calls.append(.propose(text, timezone))
    return try proposeResult.get()
  }

  func create(sessionId: String, proposal: Loci_Chat_WatchProposal) async throws(WatchError) -> Loci_Chat_CreateWatchResponse {
    calls.append(.create(sessionId, proposal.title))
    return try createResult.get()
  }

  func list(sessionId: String?) async throws(WatchError) -> [Loci_Chat_Watch] {
    calls.append(.list(sessionId))
    return try listResult.get()
  }

  func delete(id: String) async throws(WatchError) {
    calls.append(.delete(id))
    if let deleteError { throw deleteError }
  }

  func history(sessionId: String) async throws(WatchError) -> [Loci_Chat_ConversationMessage] {
    calls.append(.history(sessionId))
    return historyResult
  }
}

@MainActor struct MuseThreadFlowTests {
  private let request = "Every morning at 8, tell me if it'll rain in Lisbon"

  @Test func offerProposesWithTheUsersZone() async {
    let service = StubStandingTaskService()
    let thread = MuseThread(service: service, timezone: "Europe/Lisbon")
    await thread.offer(request)
    #expect(await service.calls == [.propose(request, "Europe/Lisbon")])
    #expect(thread.request == request)
    #expect(thread.card == .proposal(.preview))
  }

  @Test func confirmCreatesAndAppendsTheConfirmation() async throws {
    let service = StubStandingTaskService()
    let thread = MuseThread(service: service, timezone: "UTC")
    await thread.offer(request)
    await thread.confirm(sessionId: "session-1")

    #expect(await service.calls.last == .create("session-1", Loci_Chat_WatchProposal.preview.title))
    #expect(thread.card == nil)
    #expect(thread.request == nil)
    #expect(thread.confirmedWatchId == "w-1")
    #expect(thread.messages.map(\.role) == [.user, .agent])
    #expect(thread.messages.first?.text == request)
    let confirmation = try #require(thread.messages.last)
    #expect(confirmation.caption == "Standing task")
    #expect(confirmation.text.hasPrefix("Got it"))
  }

  @Test func notNowCallsNothingFurther() async {
    let service = StubStandingTaskService()
    let thread = MuseThread(service: service, timezone: "UTC")
    await thread.offer(request)
    thread.dismiss()
    #expect(await service.calls.count == 1)
    #expect(thread.card == nil)
    #expect(thread.request == nil)
    #expect(thread.messages.isEmpty)
  }

  @Test func notUnderstoodShowsTheFriendlyCopy() async {
    let thread = MuseThread(service: StubStandingTaskService(propose: .failure(.notUnderstood)), timezone: "UTC")
    await thread.offer("keep an eye on it")
    #expect(thread.card == .failed(.notUnderstood, proposal: nil))
  }

  @Test func overTheLimitKeepsTheProposalAndAddsNothing() async {
    let service = StubStandingTaskService(create: .failure(.tooMany))
    let thread = MuseThread(service: service, timezone: "UTC")
    await thread.offer(request)
    await thread.confirm(sessionId: "session-1")
    #expect(thread.card == .failed(.tooMany, proposal: .preview))
    #expect(thread.messages.isEmpty)
  }

  @Test func aFailedConfirmCanBeRetried() async {
    let service = StubStandingTaskService(create: .failure(.offline))
    let thread = MuseThread(service: service, timezone: "UTC")
    await thread.offer(request)
    await thread.confirm(sessionId: "session-1")
    await service.setCreate(.success(StubStandingTaskService.created()))
    await thread.confirm(sessionId: "session-1")
    #expect(thread.card == nil)
    #expect(thread.messages.count == 2)
    #expect(await service.calls.filter { if case .create = $0 { true } else { false } }.count == 2)
  }

  @Test func historyAddsOnlyProactiveMessages() async {
    var reply = Loci_Chat_ConversationMessage()
    reply.id = "r"
    reply.role = .assistant
    reply.content = "Here is the plan."
    var proactive = reply
    proactive.id = "p"
    proactive.content = "Rain from 14:00."
    proactive.origin = .proactive
    proactive.sourceLabel = "Standing task"
    let service = StubStandingTaskService(history: [reply, proactive])
    let thread = MuseThread(service: service, timezone: "UTC")
    await thread.loadHistory(sessionId: "session-1")
    #expect(thread.messages.map(\.id) == ["p"])
  }

  @Test func reloadingAfterAConfirmDoesNotDuplicateIt() async {
    let service = StubStandingTaskService()
    let thread = MuseThread(service: service, timezone: "UTC")
    await thread.offer(request)
    await thread.confirm(sessionId: "session-1")
    await service.setHistory([StubStandingTaskService.created().confirmation])
    await thread.loadHistory(sessionId: "session-1")
    #expect(thread.messages.filter { $0.id == "confirm-w-1" }.count == 1)
  }
}

@MainActor struct StandingTasksStoreTests {
  private func watch(_ id: String) -> Loci_Chat_Watch {
    var watch = Loci_Chat_Watch()
    watch.id = id
    watch.title = "Task \(id)"
    return watch
  }

  @Test func loadListsEveryWatch() async {
    let service = StubStandingTaskService(list: .success([watch("a"), watch("b")]))
    let store = StandingTasksStore(service: service)
    await store.load()
    #expect(store.watches?.map(\.id) == ["a", "b"])
    #expect(await service.calls == [.list(nil)])
  }

  @Test func deleteRemovesTheRow() async {
    let service = StubStandingTaskService()
    let store = StandingTasksStore(service: service, watches: [watch("a"), watch("b")])
    await store.delete(watch("a"))
    #expect(store.watches?.map(\.id) == ["b"])
    #expect(await service.calls == [.delete("a")])
  }

  @Test func deletingOneAlreadyGoneStillRemovesIt() async {
    let store = StandingTasksStore(service: StubStandingTaskService(deleteError: .notFound), watches: [watch("a")])
    await store.delete(watch("a"))
    #expect(store.watches?.isEmpty == true)
    #expect(store.error == nil)
  }

  @Test func failedDeleteKeepsTheRowAndSaysWhy() async {
    let store = StandingTasksStore(service: StubStandingTaskService(deleteError: .offline), watches: [watch("a")])
    await store.delete(watch("a"))
    #expect(store.watches?.count == 1)
    #expect(store.error == WatchError.offline.errorDescription)
  }

  @Test func failedLoadShowsAnEmptyListAndTheError() async {
    let store = StandingTasksStore(service: StubStandingTaskService(list: .failure(.signedOut)))
    await store.load()
    #expect(store.watches?.isEmpty == true)
    #expect(store.error == WatchError.signedOut.errorDescription)
  }
}

extension StubStandingTaskService {
  func setCreate(_ result: Result<Loci_Chat_CreateWatchResponse, WatchError>) { createResult = result }
  func setHistory(_ history: [Loci_Chat_ConversationMessage]) { historyResult = history }
}
