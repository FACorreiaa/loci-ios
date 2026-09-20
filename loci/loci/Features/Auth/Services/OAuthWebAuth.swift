import AuthenticationServices
import Foundation
import UIKit

/// Shared pieces of the ASWebAuthenticationSession flow used by Google sign-in
/// (and later calendar connect). Kept free of the Connect client so tests can
/// cover the two bugs that made TestFlight fail: a dummy presentation window,
/// and treating user-cancel as a red banner.
public enum OAuthWebAuth {
  public static let callbackScheme = "loci"

  public static func nativeRedirectURI(provider: String) -> String {
    "\(callbackScheme)://oauth2redirect/\(provider)"
  }

  public static func isCancellation(_ error: Error) -> Bool {
    let ns = error as NSError
    return ns.domain == ASWebAuthenticationSessionError.errorDomain
      && ns.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
  }

  /// Pick a window that is actually on screen. Returning a freshly allocated
  /// `UIWindow` (not in the hierarchy) makes ASWebAuthenticationSession fail.
  public static func presentationWindow(from scenes: [UIWindowScene]) -> UIWindow? {
    let active = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    guard let scene = active else { return nil }
    if let key = scene.windows.first(where: { $0.isKeyWindow }) { return key }
    return scene.windows.first
  }
}
