import AuthenticationServices
import Foundation
import Testing

@testable import loci

struct OAuthWebAuthTests {
  @Test func nativeRedirectURIUsesLociScheme() {
    #expect(OAuthWebAuth.nativeRedirectURI(provider: "google") == "loci://oauth2redirect/google")
    #expect(OAuthWebAuth.nativeRedirectURI(provider: "apple") == "loci://oauth2redirect/apple")
  }

  @Test func canceledLoginIsRecognised() {
    let cancelled = NSError(
      domain: ASWebAuthenticationSessionError.errorDomain,
      code: ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
    )
    #expect(OAuthWebAuth.isCancellation(cancelled))
  }

  @Test func otherErrorsAreNotCancellation() {
    let other = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
    #expect(!OAuthWebAuth.isCancellation(other))
    #expect(!OAuthWebAuth.isCancellation(APIError.invalidResponse))
  }

  @Test func presentationWindowIsNilWhenThereAreNoScenes() {
    #expect(OAuthWebAuth.presentationWindow(from: []) == nil)
  }
}
