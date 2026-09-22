import Connect
import Foundation
import LociConnectProto

/// ChatService.StreamChat as an `AsyncThrowingStream` of events.
///
/// Like web's `streamChatEvents` (loci-client/src/lib/streaming/chatStream.ts):
/// if the stream fails as Unauthenticated before any event arrives, the token
/// is refreshed once and the stream reopened. Other failures end the stream
/// by throwing an `APIError`.
nonisolated struct ChatStreamClient: Sendable {
  var client: any Loci_Chat_ChatServiceClientInterface = Loci_Chat_ChatServiceClient(client: ConnectTransport.shared.protocolClient)
  var tokens: AuthTokenProvider = .shared

  func events(_ request: Loci_Chat_ChatRequest) -> AsyncThrowingStream<Loci_Chat_StreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          var retried = false
          while true {
            let outcome = try await run(request, into: continuation)
            if outcome == .unauthenticatedBeforeFirstEvent, !retried, await tokens.refresh() != nil {
              retried = true
              continue
            }
            if outcome == .unauthenticatedBeforeFirstEvent { throw APIError.unauthorized(nil) }
            break
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
    _ request: Loci_Chat_ChatRequest,
    into continuation: AsyncThrowingStream<Loci_Chat_StreamEvent, Error>.Continuation
  ) async throws -> Outcome {
    let stream = client.streamChat(headers: [:])
    try stream.send(request)
    var sawEvent = false
    return try await withTaskCancellationHandler {
      for await result in stream.results() {
        switch result {
        case .headers: continue
        case .message(let event):
          sawEvent = true
          continuation.yield(event)
        case let .complete(code, error, _):
          if code == .ok { return .finished }
          if code == .unauthenticated, !sawEvent { return .unauthenticatedBeforeFirstEvent }
          if code == .canceled { throw CancellationError() }
          let connectError = error as? ConnectError ?? ConnectError(code: code, message: nil, exception: error)
          throw APIError(connect: connectError, fallback: "The search stopped.")
        }
      }
      return .finished
    } onCancel: {
      stream.cancel()
    }
  }
}
