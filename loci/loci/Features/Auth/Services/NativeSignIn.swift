import Connect
import CryptoKit
import Foundation
import LociConnectProto

/// The half of native sign-in both providers share: a nonce for the attempt,
/// and handing the provider's ID token to the server.
///
/// The Apple sheet and the Google SDK each return an ID token signed by the
/// provider. The server verifies it (signature, audience, expiry) and checks the
/// nonce, so a token from an earlier attempt, or one issued to another app,
/// cannot sign anybody in. Apple is sent the SHA-256 of the nonce and puts that
/// digest in the token; Google is sent the nonce itself. The server is always
/// given the raw value and knows which to expect.
public enum NativeSignIn {
  /// 32 random bytes, URL-safe base64 — comfortably inside the server's
  /// 16...256 character bound.
  public static func makeNonce() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
    return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  /// Lowercase hex SHA-256, the form Apple puts in the token's `nonce` claim.
  public static func sha256Hex(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  /// Exchanges a verified-by-server ID token for a Loci session and stores it.
  @MainActor public static func signIn(
    provider: Loci_CustomAuth_OAuthProvider,
    idToken: String,
    nonce: String,
    fullName: String = "",
    client: Loci_CustomAuth_CustomAuthServiceClient = Loci_CustomAuth_CustomAuthServiceClient(
      client: ConnectTransport.shared.protocolClient
    ),
    sessionManager: AuthSessionManager = .shared
  ) async throws -> Loci_CustomAuth_OAuthCallbackResponse {
    var req = Loci_CustomAuth_SignInWithIDTokenRequest()
    req.provider = provider
    req.idToken = idToken
    req.nonce = nonce
    req.fullName = fullName

    let res = await client.signInWithIdtoken(request: req, headers: [:])
    if let err = res.error {
      throw APIError.custom(message(for: err, provider: provider))
    }
    guard let msg = res.message else { throw APIError.invalidResponse }

    try await sessionManager.storeSession(
      accessToken: msg.accessToken,
      refreshToken: msg.refreshToken,
      userId: msg.userID,
      username: msg.username
    )
    return msg
  }

  static func message(for error: ConnectError, provider: Loci_CustomAuth_OAuthProvider) -> String {
    let name = provider == .apple ? "Apple" : "Google"
    switch error.code {
    case .failedPrecondition, .unimplemented:
      return "\(name) sign-in isn't available right now. Try email and password instead."
    case .unavailable, .deadlineExceeded:
      return "Couldn't reach \(name) to confirm your sign-in. Please try again."
    default:
      return "\(name) sign-in didn't finish. Please try again."
    }
  }
}
