import AuthenticationServices
import Connect
import Foundation
import GoogleSignIn
import LociConnectProto
import Testing

@testable import loci

@MainActor struct NativeSignInTests {
  @Test func nonceIsURLSafeAndWithinServerBounds() {
    let nonce = NativeSignIn.makeNonce()
    // The server refuses anything outside 16...256.
    #expect((16...256).contains(nonce.count))
    #expect(nonce.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
  }

  @Test func noncesDoNotRepeat() {
    let first = NativeSignIn.makeNonce()
    let second = NativeSignIn.makeNonce()
    #expect(first != second)
  }

  /// Apple puts this exact form (lowercase hex SHA-256) in the token, and the
  /// server recomputes it from the raw nonce, so both sides must agree.
  @Test func sha256HexMatchesKnownVector() {
    #expect(NativeSignIn.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }

  @Test func appleCancelIsSilent() {
    let cancel = ASAuthorizationError(.canceled)
    #expect(AppleSignInService.mapError(cancel) as? APIError == .cancelled)
    #expect(AppleSignInService.mapError(ASAuthorizationError(.failed)) as? APIError != .cancelled)
  }

  @Test func googleCancelIsSilent() {
    let cancel = NSError(domain: kGIDSignInErrorDomain, code: GIDSignInError.canceled.rawValue)
    #expect(GoogleAuthService.mapError(cancel) as? APIError == .cancelled)
    let other = NSError(domain: kGIDSignInErrorDomain, code: GIDSignInError.unknown.rawValue)
    #expect(GoogleAuthService.mapError(other) as? APIError != .cancelled)
  }

  @Test func serverErrorsBecomeReadableMessages() {
    let off = ConnectError(code: .failedPrecondition, message: nil, exception: nil, details: [], metadata: [:])
    #expect(NativeSignIn.message(for: off, provider: .apple).contains("isn't available"))
    let refused = ConnectError(code: .unauthenticated, message: nil, exception: nil, details: [], metadata: [:])
    #expect(NativeSignIn.message(for: refused, provider: .google) == "Google sign-in didn't finish. Please try again.")
  }
}
