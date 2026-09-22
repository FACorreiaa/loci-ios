import Foundation
import GoogleSignIn
import LociConnectProto
import UIKit

/// Google sign-in through the Google SDK, with no stop at the website.
///
/// This used to open the web OAuth flow and bounce back through
/// lociai.fyi/auth/oauth/google/callback. That page never loaded on devices
/// where Safari had the site's service worker, which answered every
/// navigation with the /offline page (TestFlight showed the site's "Something
/// went wrong"). And past that, the app sent the callback URL's `state` where
/// the server needed the one GetOAuthURL returned. The SDK signs in with the iOS
/// client and returns an ID token the server verifies directly.
@MainActor public final class GoogleAuthService {
  public static let shared = GoogleAuthService()

  private let clientID: String

  public init(clientID: String = AppConfig.shared.googleClientID) { self.clientID = clientID }

  public func signInWithGoogle() async throws -> Loci_CustomAuth_OAuthCallbackResponse {
    guard let presenter = Self.topViewController() else {
      throw APIError.custom("Google sign-in didn't finish. Please try again.")
    }
    let nonce = NativeSignIn.makeNonce()

    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

    let result: GIDSignInResult
    do {
      result = try await GIDSignIn.sharedInstance.signIn(
        withPresenting: presenter,
        hint: nil,
        additionalScopes: nil,
        nonce: nonce
      )
    } catch {
      throw Self.mapError(error)
    }

    guard let idToken = result.user.idToken?.tokenString else {
      throw APIError.custom("Google sign-in didn't finish. Please try again.")
    }
    // Loci keeps its own session; the SDK's copy of the Google one is not
    // needed and should not outlive this call.
    defer { GIDSignIn.sharedInstance.signOut() }

    return try await NativeSignIn.signIn(provider: .google, idToken: idToken, nonce: nonce)
  }

  /// Cancel is silent; anything else is a banner.
  nonisolated static func mapError(_ error: Error) -> Error {
    let ns = error as NSError
    if ns.domain == kGIDSignInErrorDomain, ns.code == GIDSignInError.canceled.rawValue { return APIError.cancelled }
    if error is APIError { return error }
    return APIError.custom("Google sign-in didn't finish. Please try again.")
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    var top = OAuthWebAuth.presentationWindow(from: scenes)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
