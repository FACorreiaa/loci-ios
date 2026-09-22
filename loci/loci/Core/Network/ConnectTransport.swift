import Connect
import Foundation

/// The app's Connect clients. `protocolClient` authenticates every call through
/// `AuthInterceptor`; `makeBareClient()` has no interceptors and exists for the
/// token refresh itself.
public nonisolated final class ConnectTransport: Sendable {
  public static let shared = ConnectTransport()

  public let baseURL: URL
  public let protocolClient: ProtocolClientInterface

  public init(baseURL: URL? = nil) {
    let resolved = baseURL ?? Self.configuredBaseURL
    self.baseURL = resolved
    self.protocolClient = ProtocolClient(
      httpClient: URLSessionHTTPClient(),
      config: ProtocolClientConfig(
        host: resolved.absoluteString,
        networkProtocol: .connect,
        codec: JSONCodec(),
        interceptors: [InterceptorFactory { AuthInterceptor(config: $0) }]
      )
    )
  }

  static func makeBareClient(baseURL: URL? = nil) -> ProtocolClientInterface {
    ProtocolClient(
      httpClient: URLSessionHTTPClient(),
      config: ProtocolClientConfig(
        host: (baseURL ?? configuredBaseURL).absoluteString,
        networkProtocol: .connect,
        codec: JSONCodec()
      )
    )
  }

  /// Where the MCP server lives: the API host plus `/mcp` (web: lib/mcp-endpoint.ts).
  public var mcpEndpoint: URL { baseURL.appending(path: "mcp") }

  private static var configuredBaseURL: URL {
    URL(string: AppConfig.shared.connectBaseURL) ?? URL(string: "http://localhost:8000")!
  }
}
