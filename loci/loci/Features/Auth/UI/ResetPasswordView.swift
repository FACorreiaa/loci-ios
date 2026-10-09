import LociConnectProto
import SwiftUI

/// Opened from the email link (`lociai.fyi/auth/reset-password?token=…`),
/// signed in or not: a new password twice, then sign in (web: ResetPassword).
struct ResetPasswordView: View {
  let token: String
  var onDone: (() -> Void)?

  @State private var password = ""
  @State private var confirm = ""
  @State private var problem: String?
  @State private var isSaving = false
  @State private var done = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        if done {
          Section {
            Label("Your password is changed.", systemImage: "checkmark.seal.fill").foregroundStyle(Color.lociForest)
            Text("Sign in with it on every device that still has the old one.").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
          }
        } else {
          Section("New password") {
            SecureField("New password (8+ characters)", text: $password).textContentType(.newPassword)
            SecureField("Repeat new password", text: $confirm).textContentType(.newPassword)
            if let problem { Text(problem).font(.lociCaption(12)).foregroundStyle(.red) }
          }
          Section {
            Button(isSaving ? "Saving…" : "Set new password") { Task { await save() } }
              .disabled(isSaving || password.isEmpty)
          }
        }
      }
      .navigationTitle(done ? "Done" : "Reset password")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if done {
          ToolbarItem(placement: .confirmationAction) { Button("Sign in") { onDone?() } }
        } else {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone?() } }
        }
      }
      .errorAlert($error)
    }
  }

  private func save() async {
    problem = AuthEdges.newPasswordProblem(password, confirm: confirm)
    guard problem == nil, let request = AuthEdges.resetRequest(token: token, newPassword: password, confirm: confirm) else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      _ = try await rpc("Could not reset your password. Ask for a new link.", request) {
        await SettingsClients.auth.resetPassword(request: $0, headers: [:])
      }
      done = true
      Analytics.capture(.passwordReset)
    } catch {
      if !error.isCancellation { self.error = error.userMessage }
    }
  }
}

/// Opened from `lociai.fyi/auth/confirm-email-change?token=…`: confirms at
/// once and says what happened.
struct ConfirmEmailView: View {
  let token: String
  var onDone: (() -> Void)?

  @State private var phase = Phase.working

  enum Phase: Equatable { case working, confirmed, failed(String) }

  var body: some View {
    NavigationStack {
      Group {
        switch phase {
        case .working:
          ProgressView("Confirming your new email…")
        case .confirmed:
          ContentUnavailableView("Email changed", systemImage: "checkmark.seal.fill", description: Text("Sign in with the new address from now on."))
        case .failed(let message):
          ContentUnavailableView("Could not confirm", systemImage: "envelope.badge", description: Text(message))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.lociPaper.ignoresSafeArea())
      .navigationTitle("New email")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone?() }.disabled(phase == .working) } }
      .task(id: token) { await confirm() }
    }
  }

  private func confirm() async {
    do {
      _ = try await rpc("This link has expired. Start the change again from Settings.", AuthEdges.confirmRequest(token: token)) {
        await SettingsClients.auth.confirmEmailChange(request: $0, headers: [:])
      }
      phase = .confirmed
      Analytics.capture(.emailChangeConfirmed)
    } catch {
      phase = .failed(error.userMessage)
    }
  }
}
