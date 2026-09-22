import Connect
import Foundation

/// Adds `Authorization: Bearer <access token>` to every unary call and stream,
/// unless the caller already set one. The token comes from `AuthTokenProvider`,
/// which refreshes an expired token before it is attached.
nonisolated final class AuthInterceptor: UnaryInterceptor, StreamInterceptor {
  private let tokens: AuthTokenProvider

  init(config: ProtocolClientConfig, tokens: AuthTokenProvider = .shared) { self.tokens = tokens }

  @Sendable func handleUnaryRequest<Message: ProtobufMessage>(
    _ request: HTTPRequest<Message>,
    proceed: @escaping @Sendable (Result<HTTPRequest<Message>, ConnectError>) -> Void
  ) {
    let tokens = tokens
    Task {
      let headers = await Self.headers(request.headers, tokens: tokens)
      proceed(.success(Self.copy(request, headers: headers)))
    }
  }

  @Sendable func handleStreamStart(
    _ request: HTTPRequest<Void>,
    proceed: @escaping @Sendable (Result<HTTPRequest<Void>, ConnectError>) -> Void
  ) {
    let tokens = tokens
    Task {
      let headers = await Self.headers(request.headers, tokens: tokens)
      proceed(.success(Self.copy(request, headers: headers)))
    }
  }

  private static func headers(_ headers: Headers, tokens: AuthTokenProvider) async -> Headers {
    if headers.keys.contains(where: { $0.lowercased() == "authorization" }) { return headers }
    guard let token = await tokens.accessToken() else { return headers }
    var result = headers
    result["Authorization"] = ["Bearer \(token)"]
    return result
  }

  private static func copy<T>(_ request: HTTPRequest<T>, headers: Headers) -> HTTPRequest<T> {
    HTTPRequest(
      url: request.url,
      headers: headers,
      message: request.message,
      method: request.method,
      trailers: request.trailers,
      idempotencyLevel: request.idempotencyLevel
    )
  }
}
