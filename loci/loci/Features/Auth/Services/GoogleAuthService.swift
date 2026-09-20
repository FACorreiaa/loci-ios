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
    let callbackScheme = OAuthWebAuth.callbackScheme
    let redirectUri = OAuthWebAuth.nativeRedirectURI(provider: "google")

    var req = Loci_CustomAuth_GetOAuthURLRequest()
    req.provider = .google
    req.redirectUri = redirectUri

    let res = await client.getOauthURL(request: req, headers: [:])
    if let err = res.error { throw APIError.custom("Google sign-in isn't available right now. Try email and password instead.") }
    guard let message = res.message, let authURL = URL(string: message.authURL) else { throw APIError.invalidResponse }

    let callbackURL: URL
    do {
      callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { callbackURL, error in
          if let error {
            continuation.resume(throwing: OAuthWebAuth.isCancellation(error) ? APIError.cancelled : error)
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
    } catch let error as APIError {
      throw error
    } catch {
      if OAuthWebAuth.isCancellation(error) { throw APIError.cancelled }
      throw APIError.custom("Google sign-in didn't finish. Please try again.")
    }

    guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
      throw APIError.invalidResponse
    }
    let queryItems = components.queryItems ?? []
    if let oauthError = queryItems.first(where: { $0.name == "error" })?.value, !oauthError.isEmpty {
      throw APIError.custom("Google sign-in was declined.")
    }

    let code = queryItems.first(where: { $0.name == "code" })?.value ?? ""
    let state = queryItems.first(where: { $0.name == "state" })?.value ?? message.state
    guard !code.isEmpty else { throw APIError.invalidResponse }

    var callbackReq = Loci_CustomAuth_OAuthCallbackRequest()
    callbackReq.provider = .google
    callbackReq.code = code
    callbackReq.state = state

    let callbackRes = await client.oauthCallback(request: callbackReq, headers: [:])
    if let err = callbackRes.error { throw APIError.custom("Google sign-in didn't finish. Please try again.") }
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
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      if let window = OAuthWebAuth.presentationWindow(from: scenes) { return window }
      // Last resort: the key window of the first scene. Never a detached UIWindow —
      // ASWebAuthenticationSession treats that as a failed session (error 1).
      if let scene = scenes.first {
        let window = UIWindow(windowScene: scene)
        window.makeKeyAndVisible()
        return window
      }
      return ASPresentationAnchor()
    }
  }
}
