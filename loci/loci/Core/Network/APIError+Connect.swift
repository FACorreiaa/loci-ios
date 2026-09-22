import Connect
import Foundation

/// Run a unary call; if the server says the token is no longer good, refresh once
/// and run it again. The interceptor reads the refreshed token from the Keychain,
/// so the retry carries it without the caller doing anything.
///
/// Mirrors the retry-once half of the web client's tokenRefreshInterceptor.
nonisolated func withAuthRetry<Output>(
  tokens: AuthTokenProvider = .shared,
  _ call: @Sendable () async -> ResponseMessage<Output>
) async -> ResponseMessage<Output> {
  let first = await call()
  guard first.code == .unauthenticated else { return first }
  guard await tokens.refresh() != nil else { return first }
  return await call()
}

nonisolated extension ResponseMessage {
  /// The message, or an `APIError` built from the Connect error.
  func unwrap(_ fallback: String) throws -> Output {
    if let message { return message }
    throw APIError(connect: error, fallback: fallback)
  }
}

nonisolated extension APIError {
  /// Map a Connect error to the app's error type. `ResourceExhausted` carries the
  /// server's quota reason header, the same one the web client reads
  /// (loci-client/src/lib/quota-error.ts).
  init(connect error: ConnectError?, fallback: String) {
    guard let error else {
      self = .invalidResponse
      return
    }
    let message = error.message ?? fallback
    switch error.code {
    case .unauthenticated: self = .unauthorized(error.message)
    case .permissionDenied: self = .forbidden(error.message)
    case .notFound: self = .notFound(error.message)
    case .alreadyExists, .aborted: self = .conflict(error.message)
    case .unavailable, .deadlineExceeded: self = .network(message)
    case .canceled: self = .cancelled
    case .resourceExhausted:
      let reason = error.metadata.first { $0.key.lowercased() == "x-loci-quota-reason" }?.value.first
      switch reason {
      case "free_daily_limit": self = .custom("You've used today's 10 free searches. They reset at midnight UTC.")
      case "fair_use": self = .custom("You've hit today's fair-use limit. Access resets at midnight UTC.")
      default: self = .custom(message)
      }
    default: self = .custom(message)
    }
  }
}
