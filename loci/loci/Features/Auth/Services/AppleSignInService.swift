import AuthenticationServices
import Foundation
import LociConnectProto
import UIKit

/// Sign in with Apple through the system sheet (Face ID, no password).
///
/// The sheet returns an identity token issued to this app's bundle ID. The
/// server keys the account on its `sub`, the same value the website's Apple
/// sign-in resolves to, so this lands on the account the person already has.
@MainActor public final class AppleSignInService: NSObject {
  public static let shared = AppleSignInService()

  private var continuation: CheckedContinuation<ASAuthorization, Error>?
  private var controller: ASAuthorizationController?

  public func signInWithApple() async throws -> Loci_CustomAuth_OAuthCallbackResponse {
    let nonce = NativeSignIn.makeNonce()

    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = [.fullName, .email]
    request.nonce = NativeSignIn.sha256Hex(nonce)

    let authorization: ASAuthorization
    do {
      authorization = try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
      }
    } catch {
      throw Self.mapError(error)
    }

    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
      let tokenData = credential.identityToken,
      let idToken = String(data: tokenData, encoding: .utf8)
    else { throw APIError.custom("Apple sign-in didn't finish. Please try again.") }

    // Apple gives the name once, on first consent, and never in the token.
    let fullName = credential.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? ""

    return try await NativeSignIn.signIn(provider: .apple, idToken: idToken, nonce: nonce, fullName: fullName)
  }

  /// Cancel is silent; anything else is a banner.
  nonisolated static func mapError(_ error: Error) -> Error {
    if let authError = error as? ASAuthorizationError, authError.code == .canceled { return APIError.cancelled }
    if error is APIError { return error }
    return APIError.custom("Apple sign-in didn't finish. Please try again.")
  }

  private func finish(_ result: Result<ASAuthorization, Error>) {
    continuation?.resume(with: result)
    continuation = nil
    controller = nil
  }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
  public nonisolated func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    MainActor.assumeIsolated { finish(.success(authorization)) }
  }

  public nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    MainActor.assumeIsolated { finish(.failure(error)) }
  }
}

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
  public nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      return OAuthWebAuth.presentationWindow(from: scenes) ?? ASPresentationAnchor()
    }
  }
}
