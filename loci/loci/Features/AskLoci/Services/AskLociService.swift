import Connect
import Foundation
import LociConnectProto

/// Why a question got no answer, in the overlay's words.
nonisolated enum AskLociFailure: Error, Equatable, Sendable {
  case unavailable
  case signedOut
  case unreachable

  init(code: Code) {
    switch code {
    case .unimplemented: self = .unavailable
    case .unauthenticated: self = .signedOut
    default: self = .unreachable
    }
  }

  var message: String {
    switch self {
    case .unavailable: "Ask Loci isn't available yet. The chat still is."
    case .signedOut: "Sign in again to ask."
    case .unreachable: "I couldn't reach Loci. Try again."
    }
  }
}

/// AssistantService. A protocol so the controller can be tested.
nonisolated protocol AskLociService: Sendable {
  func ask(_ request: Loci_Assistant_AskAssistantRequest) -> AsyncThrowingStream<Loci_Assistant_AssistantEvent, Error>
  func confirm(proposalID: String, option: Int?) async throws(TripActionError) -> Loci_Assistant_ConfirmActionResponse
  func dismiss(proposalID: String) async throws(TripActionError)
}

/// The stream follows `ChatStreamClient`: if it fails as Unauthenticated before
/// any event arrives, the token is refreshed once and the stream reopened.
nonisolated struct ConnectAskLociService: AskLociService {
  var client: any Loci_Assistant_AssistantServiceClientInterface =
    Loci_Assistant_AssistantServiceClient(client: ConnectTransport.shared.protocolClient)
  var tokens: AuthTokenProvider = .shared

  func ask(_ request: Loci_Assistant_AskAssistantRequest) -> AsyncThrowingStream<Loci_Assistant_AssistantEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          var retried = false
          while true {
            let outcome = try await run(request, into: continuation)
            guard outcome == .unauthenticatedBeforeFirstEvent else { break }
            guard !retried, await tokens.refresh() != nil else { throw AskLociFailure.signedOut }
            retried = true
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private enum Outcome { case finished, unauthenticatedBeforeFirstEvent }

  private func run(
    _ request: Loci_Assistant_AskAssistantRequest,
    into continuation: AsyncThrowingStream<Loci_Assistant_AssistantEvent, Error>.Continuation
  ) async throws -> Outcome {
    let stream = client.askAssistant(headers: [:])
    try stream.send(request)
    var sawEvent = false
    return try await withTaskCancellationHandler {
      for await result in stream.results() {
        switch result {
        case .headers: continue
        case .message(let event):
          sawEvent = true
          continuation.yield(event)
        case let .complete(code, _, _):
          if code == .ok { return .finished }
          if code == .unauthenticated, !sawEvent { return .unauthenticatedBeforeFirstEvent }
          if code == .canceled { throw CancellationError() }
          throw AskLociFailure(code: code)
        }
      }
      return .finished
    } onCancel: {
      stream.cancel()
    }
  }

  func confirm(proposalID: String, option: Int?) async throws(TripActionError) -> Loci_Assistant_ConfirmActionResponse {
    var request = Loci_Assistant_ConfirmActionRequest()
    request.proposalID = proposalID
    if let option { request.optionIndex = Int32(option) }
    let sent = request
    let response = await withAuthRetry { await client.confirmAction(request: sent, headers: [:]) }
    if let message = response.message { return message }
    throw TripActionError(response.error, fallback: "Couldn't make that change.")
  }

  func dismiss(proposalID: String) async throws(TripActionError) {
    var request = Loci_Assistant_DismissActionRequest()
    request.proposalID = proposalID
    let sent = request
    let response = await withAuthRetry { await client.dismissAction(request: sent, headers: [:]) }
    if response.message == nil { throw TripActionError(response.error, fallback: "Couldn't dismiss that.") }
  }
}
