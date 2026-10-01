import Foundation
import Testing

@testable import loci

/// The server's invite errors are log strings ("not found", "that is you");
/// the screen gets fixed wording by error kind, never the raw text.
struct InviteFailureTests {
  @Test func notFoundIsExpired() {
    let failure = InviteFailure(APIError.notFound("not found"))
    #expect(failure == .expired)
    #expect(failure.title(for: .open) == "This invite has expired.")
    #expect(failure.title(for: .accept) == "This invite has expired.")
    #expect(failure.hint == "Ask your friend for a new link.")
  }

  @Test func otherServerErrorsNeverShowTheRawMessage() {
    let failure = InviteFailure(APIError.custom("that is you"))
    #expect(failure == .other)
    #expect(failure.title(for: .accept) == "Could not accept the invite.")
    #expect(failure.title(for: .open) == "Could not open the invite.")
    #expect(InviteFailure(APIError.custom("something went wrong, try again")).title(for: .accept) == "Could not accept the invite.")
  }

  @Test func offlineAndSignedOut() {
    #expect(InviteFailure(APIError.network("unavailable")) == .offline)
    #expect(InviteFailure(APIError.unauthorized("token expired")) == .signedOut)
    #expect(InviteFailure(APIError.network("x")).hint != "Ask your friend for a new link.")
  }

  @Test func nonAPIErrorIsOther() {
    #expect(InviteFailure(URLError(.badURL)) == .other)
  }
}
