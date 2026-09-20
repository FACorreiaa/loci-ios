import Connect
import Foundation

public final class ConnectTransport: @unchecked Sendable {
  public static let shared = ConnectTransport()

  public private(set) var baseURL: URL
  private var client: ProtocolClient

  public init(baseURL: URL? = nil) {
    let resolved = baseURL ?? (URL(string: AppConfig.shared.connectBaseURL) ?? URL(string: "http://localhost:8000")!)
    self.baseURL = resolved
    self.client = ProtocolClient(
      httpClient: URLSessionHTTPClient(),
      config: ProtocolClientConfig(host: resolved.absoluteString, networkProtocol: .connect, codec: JSONCodec())
    )
  }

  public func updateBaseURL(_ newURL: URL) {
    self.baseURL = newURL
    self.client = ProtocolClient(
      httpClient: URLSessionHTTPClient(),
      config: ProtocolClientConfig(host: newURL.absoluteString, networkProtocol: .connect, codec: JSONCodec())
    )
  }

  public var protocolClient: ProtocolClientInterface { client }
}
