import Connect
import Foundation
import LociConnectProto

/// What the Muse thread and the Standing tasks screen need from the server:
/// WatchService (loci.chat) plus the stored thread for proactive messages.
/// Behind a protocol so tests and design previews run without a session.
nonisolated protocol StandingTaskService: Sendable {
  func propose(text: String, timezone: String) async throws(WatchError) -> Loci_Chat_WatchProposal
  func create(sessionId: String, proposal: Loci_Chat_WatchProposal) async throws(WatchError) -> Loci_Chat_CreateWatchResponse
  func list(sessionId: String?) async throws(WatchError) -> [Loci_Chat_Watch]
  func delete(id: String) async throws(WatchError)
  /// The thread's stored messages (GetChatSession), for the proactive ones.
  func history(sessionId: String) async throws(WatchError) -> [Loci_Chat_ConversationMessage]
}

/// A WatchService failure, by Connect code, with the copy the user sees.
nonisolated enum WatchError: LocalizedError, Equatable, Sendable {
  /// InvalidArgument: the server could not turn the text into a standing task.
  case notUnderstood
  /// NotFound: the conversation (create) or the task (delete) is gone.
  case notFound
  /// ResourceExhausted: already at the limit of 10.
  case tooMany
  /// Unauthenticated, after the refresh-and-retry already failed.
  case signedOut
  /// Unavailable, DeadlineExceeded, or no response at all.
  case offline
  case other

  init(code: Code) {
    switch code {
    case .invalidArgument, .failedPrecondition, .outOfRange: self = .notUnderstood
    case .notFound: self = .notFound
    case .resourceExhausted: self = .tooMany
    case .unauthenticated, .permissionDenied: self = .signedOut
    case .unavailable, .deadlineExceeded, .unknown: self = .offline
    default: self = .other
    }
  }

  var errorDescription: String? {
    switch self {
    case .notUnderstood: "I couldn't turn that into a standing task. Try something like “every morning at 8, tell me if it'll rain in Lisbon”."
    case .notFound: "That conversation or task isn't there any more."
    case .tooMany: "You already have 10 standing tasks. Remove one in Settings › Standing tasks, then try again."
    case .signedOut: "Your session has ended. Sign in again to set up standing tasks."
    case .offline: "Couldn't reach Loci. Check your connection and try again."
    case .other: "Something went wrong setting that up. Try again in a moment."
    }
  }
}

/// The live service over the app's authenticated Connect transport.
nonisolated struct ConnectStandingTaskService: StandingTaskService {
  private var watches: Loci_Chat_WatchServiceClient { Loci_Chat_WatchServiceClient(client: ConnectTransport.shared.protocolClient) }
  private var chat: Loci_Chat_ChatServiceClient { Loci_Chat_ChatServiceClient(client: ConnectTransport.shared.protocolClient) }

  func propose(text: String, timezone: String) async throws(WatchError) -> Loci_Chat_WatchProposal {
    var request = Loci_Chat_ProposeWatchRequest()
    request.text = text
    request.timezone = timezone
    let watches = self.watches
    return try await Self.call { [request] in await watches.proposeWatch(request: request, headers: [:]) }.proposal
  }

  func create(sessionId: String, proposal: Loci_Chat_WatchProposal) async throws(WatchError) -> Loci_Chat_CreateWatchResponse {
    var request = Loci_Chat_CreateWatchRequest()
    request.sessionID = sessionId
    request.proposal = proposal
    let watches = self.watches
    return try await Self.call { [request] in await watches.createWatch(request: request, headers: [:]) }
  }

  func list(sessionId: String?) async throws(WatchError) -> [Loci_Chat_Watch] {
    var request = Loci_Chat_ListWatchesRequest()
    if let sessionId { request.sessionID = sessionId }
    let watches = self.watches
    return try await Self.call { [request] in await watches.listWatches(request: request, headers: [:]) }.watches
  }

  func delete(id: String) async throws(WatchError) {
    var request = Loci_Chat_DeleteWatchRequest()
    request.id = id
    let watches = self.watches
    _ = try await Self.call { [request] in await watches.deleteWatch(request: request, headers: [:]) }
  }

  func history(sessionId: String) async throws(WatchError) -> [Loci_Chat_ConversationMessage] {
    var request = Loci_Chat_GetChatSessionRequest()
    request.sessionID = sessionId
    let chat = self.chat
    return try await Self.call { [request] in await chat.getChatSession(request: request, headers: [:]) }.session.conversationHistory
  }

  /// One unary call with the app's refresh-and-retry-once policy, failures by code.
  private static func call<Output>(_ call: @Sendable () async -> ResponseMessage<Output>) async throws(WatchError) -> Output {
    let response = await withAuthRetry(call)
    if let message = response.message { return message }
    throw WatchError(code: response.error?.code ?? response.code)
  }
}
