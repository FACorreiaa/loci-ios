import CoreImage.CIFilterBuiltins
import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Security (web: settings tab "security"): ChangePassword, two-factor, and
/// signed-in devices. All AuthService.
struct SecuritySettingsView: View {
  var body: some View {
    List {
      Section { NavigationLink("Change password") { ChangePasswordView() } }
      TwoFactorSection()
      SignedInDevicesSection()
    }
    .settingsStyle("Security")
  }
}

/// AuthService.ChangePassword{oldPassword, newPassword}.
struct ChangePasswordView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var oldPassword = ""
  @State private var newPassword = ""
  @State private var confirmPassword = ""
  @State private var isSaving = false
  @State private var error: String?

  private var canSave: Bool { !oldPassword.isEmpty && newPassword.count >= 8 && newPassword == confirmPassword && !isSaving }

  var body: some View {
    Form {
      SecureField("Current password", text: $oldPassword).textContentType(.password)
      SecureField("New password (8+ characters)", text: $newPassword).textContentType(.newPassword)
      SecureField("Repeat new password", text: $confirmPassword).textContentType(.newPassword)
      if !confirmPassword.isEmpty, newPassword != confirmPassword {
        Text("The new passwords don't match.").foregroundStyle(Color.lociDestructive)
      }
    }
    .settingsStyle("Change password")
    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(!canSave) } }
    .errorAlert($error)
  }

  private func save() async {
    isSaving = true
    defer { isSaving = false }
    var request = Loci_Auth_ChangePasswordRequest()
    request.oldPassword = oldPassword
    request.newPassword = newPassword
    do {
      _ = try await rpc("Could not change your password.", request) { await SettingsClients.auth.changePassword(request: $0, headers: [:]) }
      dismiss()
    } catch { self.error = error.userMessage }
  }
}

/// Two-factor: GetMFAStatus, BeginMFAEnrollment, ConfirmMFAEnrollment{code},
/// DisableMFA{code}, RegenerateRecoveryCodes{code}.
struct TwoFactorSection: View {
  @State private var status: Loci_Auth_GetMFAStatusResponse?
  @State private var enrollment: Loci_Auth_BeginMFAEnrollmentResponse?
  @State private var code = ""
  @State private var recoveryCodes: [String] = []
  @State private var error: String?

  var body: some View {
    Section {
      if let status {
        if status.enabled {
          LabeledContent("Status", value: "On")
          LabeledContent("Recovery codes left", value: "\(status.recoveryCodesRemaining)")
          TextField("Code from your authenticator", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
          Button("New recovery codes") { Task { await regenerate() } }.disabled(code.count < 6)
          if !status.requiredByPolicy {
            Button("Turn off two-factor", role: .destructive) { Task { await disable() } }.disabled(code.count < 6)
          }
        } else if let enrollment {
          if let qr = QRCode.image(for: enrollment.provisioningUri) {
            Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 200).frame(maxWidth: .infinity)
          }
          LabeledContent("Setup key") { Text(enrollment.secret).font(.lociCoord(12)).textSelection(.enabled) }
          if let url = URL(string: enrollment.provisioningUri) { Link("Open in authenticator app", destination: url) }
          TextField("6-digit code", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
          Button("Confirm") { Task { await confirm() } }.disabled(code.count < 6)
        } else {
          LabeledContent("Status", value: "Off")
          Button("Turn on two-factor") { Task { await begin() } }
        }
      } else {
        ProgressView()
      }
      if !recoveryCodes.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Save these recovery codes. Each works once.").font(.lociCaption())
          ForEach(recoveryCodes, id: \.self) { Text($0).font(.lociCoord(13)) }
        }.textSelection(.enabled)
        Button("Copy codes") { UIPasteboard.general.string = recoveryCodes.joined(separator: "\n") }
      }
    } header: {
      Text("Two-factor authentication")
    }
    .errorAlert($error)
    .task { await load() }
  }

  private func load() async {
    do {
      status = try await rpc("Could not load two-factor status.") { await SettingsClients.auth.getMfastatus(request: .init(), headers: [:]) }
    } catch { self.error = error.userMessage }
  }

  private func begin() async {
    do {
      enrollment = try await rpc("Could not start setup.") { await SettingsClients.auth.beginMfaenrollment(request: .init(), headers: [:]) }
    } catch { self.error = error.userMessage }
  }

  private func confirm() async {
    var request = Loci_Auth_ConfirmMFAEnrollmentRequest()
    request.code = code
    do {
      let response = try await rpc("That code didn't work.", request) {
        await SettingsClients.auth.confirmMfaenrollment(request: $0, headers: [:])
      }
      recoveryCodes = response.recoveryCodes
      enrollment = nil
      code = ""
      await load()
    } catch { self.error = error.userMessage }
  }

  private func disable() async {
    var request = Loci_Auth_DisableMFARequest()
    request.code = code
    do {
      _ = try await rpc("That code didn't work.", request) { await SettingsClients.auth.disableMfa(request: $0, headers: [:]) }
      code = ""
      recoveryCodes = []
      await load()
    } catch { self.error = error.userMessage }
  }

  private func regenerate() async {
    var request = Loci_Auth_RegenerateRecoveryCodesRequest()
    request.code = code
    do {
      recoveryCodes = try await rpc("That code didn't work.", request) {
        await SettingsClients.auth.regenerateRecoveryCodes(request: $0, headers: [:])
      }.recoveryCodes
      code = ""
      await load()
    } catch { self.error = error.userMessage }
  }
}

/// Signed-in devices: ListSessions{refreshToken}, RevokeSession{sessionId},
/// RevokeOtherSessions{refreshToken}. The refresh token lets the server mark
/// which session is this phone.
struct SignedInDevicesSection: View {
  @State private var sessions: [Loci_Auth_DeviceSession] = []
  @State private var error: String?

  var body: some View {
    Section {
      ForEach(sessions, id: \.id) { session in
        VStack(alignment: .leading, spacing: 2) {
          Text(session.hasUserAgent ? session.userAgent : "Unknown device").lineLimit(1)
          HStack {
            if session.current { Text("This device").foregroundStyle(Color.lociForest) }
            if session.hasCreatedAt { Text(session.createdAt.date, style: .date) }
          }.font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        }
        .swipeActions {
          if !session.current { Button("Sign out", role: .destructive) { Task { await revoke(session.id) } } }
        }
      }
      if sessions.count > 1 {
        Button("Sign out everywhere else", role: .destructive) { Task { await revokeOthers() } }
      }
    } header: {
      Text("Signed-in devices")
    }
    .errorAlert($error)
    .task { await load() }
  }

  private func load() async {
    var request = Loci_Auth_ListSessionsRequest()
    if let token = try? await AuthSessionManager.shared.getRefreshToken(), !token.isEmpty { request.refreshToken = token }
    do {
      sessions = try await rpc("Could not load your devices.", request) {
        await SettingsClients.auth.listSessions(request: $0, headers: [:])
      }.sessions
    } catch { self.error = error.userMessage }
  }

  private func revoke(_ id: String) async {
    var request = Loci_Auth_RevokeSessionRequest()
    request.sessionID = id
    do {
      _ = try await rpc("Could not sign that device out.", request) { await SettingsClients.auth.revokeSession(request: $0, headers: [:]) }
      await load()
    } catch { self.error = error.userMessage }
  }

  private func revokeOthers() async {
    guard let token = try? await AuthSessionManager.shared.getRefreshToken(), !token.isEmpty else { return }
    var request = Loci_Auth_RevokeOtherSessionsRequest()
    request.refreshToken = token
    do {
      _ = try await rpc("Could not sign the other devices out.", request) {
        await SettingsClients.auth.revokeOtherSessions(request: $0, headers: [:])
      }
      await load()
    } catch { self.error = error.userMessage }
  }
}

/// A QR code for the authenticator `otpauth://` URI, drawn on device.
enum QRCode {
  static func image(for string: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
      let cgImage = CIContext().createCGImage(output, from: output.extent)
    else { return nil }
    return UIImage(cgImage: cgImage)
  }
}
