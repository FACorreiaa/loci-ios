import Connect
import Foundation
import LociConnectProto

/// Keychain keys shared by the session manager and the token provider.
nonisolated enum AuthKeychainKeys {
  static let accessToken = "loci_auth_access_token"
  static let refreshToken = "loci_auth_refresh_token"
  static let userId = "loci_auth_user_id"
  static let username = "loci_auth_username"
}

/// Outcome of one AuthService.RefreshToken call.
nonisolated enum TokenRefreshResult: Sendable, Equatable {
  case refreshed(accessToken: String, refreshToken: String)
  /// The server rejected the refresh token: the session is over.
  case rejected
  /// Network or server trouble: keep the session and try again later.
  case unavailable
}

/// The single source of access tokens for every Connect call.
///
/// Mirrors the web client's `tokenRefreshInterceptor` (loci-client/src/lib/connect-transport.ts):
/// one refresh at a time, shared by every caller that needs it, run on a transport
/// with no interceptors so the refresh cannot recurse into itself.
actor AuthTokenProvider {
  static let shared = AuthTokenProvider()

  /// Treat a token as expired this long before its `exp`, so a request does not
  /// leave with a token that dies in flight.
  static let expirySkew: TimeInterval = 30

  private let store: SecureStringStoring
  private let performRefresh: @Sendable (String) async -> TokenRefreshResult
  private let onSessionEnded: @Sendable () async -> Void
  private let now: @Sendable () -> Date
  private var inFlight: Task<String?, Never>?

  init(
    store: SecureStringStoring = KeychainStringStore(),
    performRefresh: (@Sendable (String) async -> TokenRefreshResult)? = nil,
    onSessionEnded: (@Sendable () async -> Void)? = nil,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.store = store
    self.performRefresh = performRefresh ?? AuthTokenProvider.refreshOverNetwork
    self.onSessionEnded = onSessionEnded ?? { await AuthSessionManager.shared.invalidateSession() }
    self.now = now
  }

  /// A token that is valid now, refreshing first if the stored one has expired.
  /// Returns nil when signed out, or when a refresh was needed and could not complete.
  func accessToken() async -> String? {
    guard let token = try? store.string(for: AuthKeychainKeys.accessToken), !token.isEmpty else { return nil }
    if let expiry = JWTTokenInspector.expirationDate(in: token), expiry.addingTimeInterval(-Self.expirySkew) <= now() {
      return await refresh()
    }
    return token
  }

  /// Refresh the session. Concurrent callers share one network call.
  func refresh() async -> String? {
    if let inFlight { return await inFlight.value }
    let task = Task { await runRefresh() }
    inFlight = task
    let token = await task.value
    inFlight = nil
    return token
  }

  private func runRefresh() async -> String? {
    guard let refreshToken = try? store.string(for: AuthKeychainKeys.refreshToken), !refreshToken.isEmpty else {
      await onSessionEnded()
      return nil
    }
    switch await performRefresh(refreshToken) {
    case let .refreshed(access, refresh):
      try? store.setString(access, for: AuthKeychainKeys.accessToken)
      if !refresh.isEmpty { try? store.setString(refresh, for: AuthKeychainKeys.refreshToken) }
      return access
    case .rejected:
      await onSessionEnded()
      return nil
    case .unavailable:
      return nil
    }
  }

  private static let refreshClient = Loci_Auth_AuthServiceClient(client: ConnectTransport.makeBareClient())

  private static let refreshOverNetwork: @Sendable (String) async -> TokenRefreshResult = { refreshToken in
    var request = Loci_Auth_RefreshTokenRequest()
    request.refreshToken = refreshToken
    let response = await refreshClient.refreshToken(request: request, headers: [:])
    if let message = response.message, !message.accessToken.isEmpty {
      return .refreshed(accessToken: message.accessToken, refreshToken: message.refreshToken)
    }
    switch response.code {
    case .unauthenticated, .invalidArgument, .permissionDenied, .notFound: return .rejected
    default: return .unavailable
    }
  }
}
