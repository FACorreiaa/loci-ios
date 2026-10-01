import LociConnectProto
import SwiftUI

/// AuthService.ChangeEmail{password, newEmail}: the server mails a link to the
/// new address; nothing changes until it is tapped (`ConfirmEmailView`).
struct ChangeEmailView: View {
  @State private var password = ""
  @State private var newEmail = ""
  @State private var problem: String?
  @State private var isSaving = false
  @State private var sentTo: String?
  @State private var error: String?

  var body: some View {
    Form {
      if let sentTo {
        Section {
          Label("Check your inbox", systemImage: "envelope.badge").foregroundStyle(Color.lociForest)
          Text("We sent a link to \(sentTo). Your email changes when you open it; until then the old one keeps working.")
            .font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        }
      } else {
        Section {
          SecureField("Current password", text: $password).textContentType(.password)
          TextField("New email address", text: $newEmail)
            .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
          if let problem { Text(problem).font(.lociCaption(12)).foregroundStyle(.red) }
        } footer: {
          Text("We will send a confirmation link to the new address.")
        }
      }
    }
    .settingsStyle("Change email")
    .toolbar {
      if sentTo == nil {
        ToolbarItem(placement: .confirmationAction) { Button("Send link") { Task { await send() } }.disabled(isSaving || newEmail.isEmpty) }
      }
    }
    .errorAlert($error)
  }

  private func send() async {
    problem = AuthEdges.emailChangeProblem(password: password, newEmail: newEmail)
    guard problem == nil, let request = AuthEdges.changeEmailRequest(password: password, newEmail: newEmail) else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      _ = try await rpc("Could not start the email change.", request) { await SettingsClients.auth.changeEmail(request: $0, headers: [:]) }
      sentTo = request.newEmail
      Analytics.capture(.emailChangeRequested)
    } catch {
      if !error.isCancellation { self.error = error.userMessage }
    }
  }
}
