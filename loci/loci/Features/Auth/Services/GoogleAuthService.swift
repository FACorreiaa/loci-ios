import AuthenticationServices
import Connect
import Foundation
import LociConnectProto
import UIKit

@MainActor public final class GoogleAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
  public static let shared = GoogleAuthService()

  private let client: Loci_CustomAuth_CustomAuthServiceClient
  private let sessionManager: AuthSessionManager
  private var webAuthSession: ASWebAuthenticationSession?

  public init(client: Loci_CustomAuth_CustomAuthServiceClient? = nil, sessionManager: AuthSessionManager? = nil) {
    self.client = client ?? Loci_CustomAuth_CustomAuthServiceClient(client: ConnectTransport.shared.protocolClient)
    self.sessionManager = sessionManager ?? .shared
  }

  public func signInWithGoogle() async throws -> Loci_CustomAuth_OAuthCallbackResponse {
    let callbackScheme = "loci"
    let redirectUri = "\(callbackScheme)://oauth2redirect/google"

    var req = Loci_CustomAuth_GetOAuthURLRequest()
    req.provider = .google
    req.redirectUri = redirectUri

    let res = await client.getOauthURL(request: req, headers: [:])
    if let err = res.error { throw APIError.custom(err.message ?? "Failed to initialize Google authentication.") }
    guard let message = res.message, let authURL = URL(string: message.authURL) else { throw APIError.invalidResponse }

    let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
      let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { callbackURL, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let callbackURL {
          continuation.resume(returning: callbackURL)
        } else {
          continuation.resume(throwing: APIError.invalidResponse)
        }
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false
      self.webAuthSession = session
      session.start()
    }

    guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false), let queryItems = components.queryItems else {
      throw APIError.invalidResponse
    }

    let code = queryItems.first(where: { $0.name == "code" })?.value ?? ""
    let state = queryItems.first(where: { $0.name == "state" })?.value ?? message.state

    var callbackReq = Loci_CustomAuth_OAuthCallbackRequest()
    callbackReq.provider = .google
    callbackReq.code = code
    callbackReq.state = state

    let callbackRes = await client.oauthCallback(request: callbackReq, headers: [:])
    if let err = callbackRes.error { throw APIError.custom(err.message ?? "Google authentication failed.") }
    guard let callbackMsg = callbackRes.message else { throw APIError.invalidResponse }

    try await sessionManager.storeSession(
      accessToken: callbackMsg.accessToken,
      refreshToken: callbackMsg.refreshToken,
      userId: callbackMsg.userID,
      username: callbackMsg.username
    )

    return callbackMsg
  }

  public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      if let activeScene = windowScenes.first(where: { $0.activationState == .foregroundActive }) ?? windowScenes.first {
        if let keyWindow = activeScene.windows.first(where: { $0.isKeyWindow }) { return keyWindow }
        return UIWindow(windowScene: activeScene)
      }
      return UIWindow()
    }
  }
}
