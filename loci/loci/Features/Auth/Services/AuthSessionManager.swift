import Foundation

public extension Notification.Name {
  /// A session was stored. `userInfo[AuthSessionUserInfo.isNewUser]` is true
  /// when this sign-in created the account (email sign-up, or a native sign-in
  /// the server reported as new).
  static let authSessionDidAuthenticate = Notification.Name("loci.authSessionDidAuthenticate")
  static let authSessionWillInvalidate = Notification.Name("loci.authSessionWillInvalidate")
  static let authSessionDidInvalidate = Notification.Name("loci.authSessionDidInvalidate")
}

public enum AuthSessionUserInfo {
  public static let isNewUser = "isNewUser"
}

public protocol AuthSessionManaging: Sendable {
  func restoreSessionIfNeeded() async -> Bool
  func validAccessToken() async throws -> String?
  func getRefreshToken() async throws -> String?
  func storeSession(accessToken: String, refreshToken: String?, userId: String?, username: String?, isNewUser: Bool) async throws
  func logout() async
  func invalidateSession() async

  var currentUserID: String? { get }
  var currentUsername: String? { get }
}

public final class AuthSessionManager: AuthSessionManaging, @unchecked Sendable {
  public static let shared = AuthSessionManager()

  private let secureStore: SecureStringStoring
  private let accessTokenKey = AuthKeychainKeys.accessToken
  private let refreshTokenKey = AuthKeychainKeys.refreshToken
  private let userIdKey = AuthKeychainKeys.userId
  private let usernameKey = AuthKeychainKeys.username

  public private(set) var currentUserID: String?
  public private(set) var currentUsername: String?

  public init(secureStore: SecureStringStoring = KeychainStringStore()) {
    self.secureStore = secureStore
    self.currentUserID = try? secureStore.string(for: userIdKey)
    self.currentUsername = try? secureStore.string(for: usernameKey)
  }

  /// True when there is a session to resume. An expired access token is refreshed
  /// here; if the refresh cannot reach the server, the session is kept (the refresh
  /// token is still in the Keychain) and the next call retries it.
  public func restoreSessionIfNeeded() async -> Bool {
    if let token = try? await validAccessToken(), !token.isEmpty { return true }
    return !((try? secureStore.string(for: refreshTokenKey))?.isEmpty ?? true)
  }

  /// A usable access token, refreshed first if the stored one has expired.
  public func validAccessToken() async throws -> String? { await AuthTokenProvider.shared.accessToken() }

  public func getRefreshToken() async throws -> String? { try secureStore.string(for: refreshTokenKey) }

  public func storeSession(
    accessToken: String,
    refreshToken: String?,
    userId: String?,
    username: String?,
    isNewUser: Bool = false
  ) async throws {
    try secureStore.setString(accessToken, for: accessTokenKey)
    if let refreshToken, !refreshToken.isEmpty { try secureStore.setString(refreshToken, for: refreshTokenKey) }
    if let userId, !userId.isEmpty {
      try secureStore.setString(userId, for: userIdKey)
      self.currentUserID = userId
    }
    if let username, !username.isEmpty {
      try secureStore.setString(username, for: usernameKey)
      self.currentUsername = username
    }

    await MainActor.run {
      NotificationCenter.default.post(name: .authSessionDidAuthenticate, object: nil, userInfo: [AuthSessionUserInfo.isNewUser: isNewUser])
    }
  }

  public func logout() async { await invalidateSession() }

  public func invalidateSession() async {
    try? secureStore.removeValue(for: accessTokenKey)
    try? secureStore.removeValue(for: refreshTokenKey)
    try? secureStore.removeValue(for: userIdKey)
    try? secureStore.removeValue(for: usernameKey)
    self.currentUserID = nil
    self.currentUsername = nil

    await MainActor.run { NotificationCenter.default.post(name: .authSessionDidInvalidate, object: nil) }
  }
}
