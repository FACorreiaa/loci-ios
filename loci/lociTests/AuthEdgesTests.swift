import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Pass 3, Phase 8: change email, confirm it from the link, reset a password
/// from the link (web: ResetPassword.tsx, Settings email change).
struct AuthEdgesTests {
  @Test func newPasswordRulesMatchWeb() {
    #expect(AuthEdges.newPasswordProblem("", confirm: "") == "Enter a new password.")
    #expect(AuthEdges.newPasswordProblem("short", confirm: "short") == "Use at least 8 characters.")
    #expect(AuthEdges.newPasswordProblem("longenough", confirm: "different") == "Those passwords don't match.")
    #expect(AuthEdges.newPasswordProblem("longenough", confirm: "longenough") == nil)
  }

  @Test func resetRequestIsOnlyBuiltWhenTheRulesPass() {
    #expect(AuthEdges.resetRequest(token: "t", newPassword: "short", confirm: "short") == nil, "a rejected form never reaches the server")
    let request = AuthEdges.resetRequest(token: "tok-123", newPassword: "longenough", confirm: "longenough")
    #expect(request?.token == "tok-123")
    #expect(request?.newPassword == "longenough")
  }

  @Test func emailChangeRulesAndRequest() {
    #expect(AuthEdges.emailChangeProblem(password: "", newEmail: "a@b.co") == "Enter your current password.")
    #expect(AuthEdges.emailChangeProblem(password: "secret12", newEmail: "nope") == "Enter a valid email address.")
    #expect(AuthEdges.emailChangeProblem(password: "secret12", newEmail: " New@Example.com ") == nil)
    let request = AuthEdges.changeEmailRequest(password: "secret12", newEmail: " New@Example.com ")
    #expect(request?.newEmail == "new@example.com", "trimmed and lowercased")
    #expect(request?.password == "secret12")
    #expect(AuthEdges.changeEmailRequest(password: "secret12", newEmail: "nope") == nil)
  }

  @Test func confirmRequestCarriesTheToken() {
    #expect(AuthEdges.confirmRequest(token: " abc ").token == "abc")
  }

  @Test func linksCarryTheTokenFromTheQuery() throws {
    let reset = try #require(AppLink(url: URL(string: "https://lociai.fyi/auth/reset-password?token=abc123")!))
    #expect(reset == .resetPassword(token: "abc123"))
    let confirm = try #require(AppLink(url: URL(string: "https://lociai.fyi/auth/confirm-email-change?token=xyz")!))
    #expect(confirm == .confirmEmail(token: "xyz"))
    #expect(AppLink(url: URL(string: "https://lociai.fyi/auth/reset-password")!) == nil, "no token, no page")
    #expect(AppLink(url: URL(string: "loci://auth/reset-password?token=abc")!) == .resetPassword(token: "abc"))
    #expect(AppLink.resetPassword(token: "x").isAuthEdge)
    #expect(AppLink.confirmEmail(token: "x").isAuthEdge)
    #expect(!AppLink.recents.isAuthEdge)
  }
}
