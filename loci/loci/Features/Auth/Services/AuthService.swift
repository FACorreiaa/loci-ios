import Connect
import Foundation
import LociConnectProto

@MainActor public final class AuthService {
  public static let shared = AuthService()
  private let client: Loci_Auth_AuthServiceClient
  private let sessionManager: AuthSessionManager

  public init(client: Loci_Auth_AuthServiceClient? = nil, sessionManager: AuthSessionManager? = nil) {
    self.client = client ?? Loci_Auth_AuthServiceClient(client: ConnectTransport.shared.protocolClient)
    self.sessionManager = sessionManager ?? .shared
  }

  public func login(email: String, password: String) async throws -> Loci_Auth_LoginResponse {
    var req = Loci_Auth_LoginRequest()
    req.email = email
    req.password = password

    let res = await client.login(request: req, headers: [:])
    if let err = res.error { throw APIError.custom(err.message ?? "Authentication failed.") }
    guard let message = res.message else { throw APIError.invalidResponse }

    if !message.mfaRequired {
      try await sessionManager.storeSession(
        accessToken: message.accessToken,
        refreshToken: message.refreshToken,
        userId: message.userID,
        username: message.username
      )
    }
    return message
  }

  public func register(email: String, username: String, password: String) async throws -> Loci_Common_Response {
    var req = Loci_Auth_RegisterRequest()
    req.email = email
    req.username = username
    req.password = password

    let res = await client.register(request: req, headers: [:])
    if let err = res.error { throw APIError.custom(err.message ?? "Registration failed.") }
    guard let message = res.message else { throw APIError.invalidResponse }
    return message
  }

  public func verifyMFA(mfaToken: String, code: String, recoveryCode: String? = nil) async throws -> Loci_Auth_LoginResponse {
    var req = Loci_Auth_VerifyMFARequest()
    req.mfaToken = mfaToken
    if let recoveryCode, !recoveryCode.isEmpty { req.recoveryCode = recoveryCode } else { req.code = code }

    let res = await client.verifyMfa(request: req, headers: [:])
    if let err = res.error { throw APIError.custom(err.message ?? "MFA verification failed.") }
    guard let message = res.message else { throw APIError.invalidResponse }

    try await sessionManager.storeSession(
      accessToken: message.accessToken,
      refreshToken: message.refreshToken,
      userId: message.userID,
      username: message.username
    )
    return message
  }

  public func forgotPassword(email: String) async throws {
    var req = Loci_Auth_ForgotPasswordRequest()
    req.email = email

    let res = await client.forgotPassword(request: req, headers: [:])
    if let err = res.error { throw APIError.custom(err.message ?? "Password reset failed.") }
  }

  public func logout() async {
    if let rToken = try? await sessionManager.getRefreshToken(), !rToken.isEmpty {
      var req = Loci_Auth_LogoutRequest()
      req.refreshToken = rToken
      _ = await client.logout(request: req, headers: [:])
    }
    await sessionManager.logout()
  }
}
