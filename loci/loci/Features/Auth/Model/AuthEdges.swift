import Foundation
import LociConnectProto

/// Change email, confirm it from the link, reset a password from the link
/// (web: ResetPassword.tsx and the Settings email change). The rules live
/// here so a rejected form never reaches the server.
nonisolated enum AuthEdges {
  static let minimumPasswordLength = 8

  /// web's validatePassword + the confirm check, first problem wins.
  static func newPasswordProblem(_ password: String, confirm: String) -> String? {
    if password.isEmpty { return "Enter a new password." }
    if password.count < minimumPasswordLength { return "Use at least \(minimumPasswordLength) characters." }
    if password != confirm { return "Those passwords don't match." }
    return nil
  }

  static func resetRequest(token: String, newPassword: String, confirm: String) -> Loci_Auth_ResetPasswordRequest? {
    guard newPasswordProblem(newPassword, confirm: confirm) == nil else { return nil }
    var request = Loci_Auth_ResetPasswordRequest()
    request.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    request.newPassword = newPassword
    return request
  }

  static func emailChangeProblem(password: String, newEmail: String) -> String? {
    if password.isEmpty { return "Enter your current password." }
    guard isEmail(normalise(newEmail)) else { return "Enter a valid email address." }
    return nil
  }

  static func changeEmailRequest(password: String, newEmail: String) -> Loci_Auth_ChangeEmailRequest? {
    guard emailChangeProblem(password: password, newEmail: newEmail) == nil else { return nil }
    var request = Loci_Auth_ChangeEmailRequest()
    request.password = password
    request.newEmail = normalise(newEmail)
    return request
  }

  static func confirmRequest(token: String) -> Loci_Auth_ConfirmEmailChangeRequest {
    var request = Loci_Auth_ConfirmEmailChangeRequest()
    request.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    return request
  }

  private static func normalise(_ email: String) -> String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

  /// Something@something.tld; the server does the real check.
  private static func isEmail(_ value: String) -> Bool {
    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty else { return false }
    let domain = parts[1]
    return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
  }
}
