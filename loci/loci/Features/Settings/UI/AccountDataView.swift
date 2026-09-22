import LociConnectProto
import SwiftUI

/// Your data (web: AccountData). UserService.ExportUserData{} and
/// DeleteAccount{confirmation: "DELETE"}.
struct AccountDataView: View {
  @State private var exportedFile: URL?
  @State private var isExporting = false
  @State private var deleteConfirmation = ""
  @State private var isDeleting = false
  @State private var error: String?

  var body: some View {
    Form {
      Section {
        if let exportedFile {
          ShareLink(item: exportedFile) { Label("Share export", systemImage: "square.and.arrow.up") }
        } else {
          Button {
            Task { await export() }
          } label: {
            HStack {
              Label("Export my data", systemImage: "arrow.down.doc")
              if isExporting { Spacer(); ProgressView() }
            }
          }.disabled(isExporting)
        }
      } footer: {
        Text("Everything your account holds, as one JSON file.")
      }

      Section {
        TextField("Type DELETE to confirm", text: $deleteConfirmation).textInputAutocapitalization(.characters).autocorrectionDisabled()
        Button("Delete my account", role: .destructive) { Task { await delete() } }.disabled(deleteConfirmation != "DELETE" || isDeleting)
      } header: {
        Text("Delete account")
      } footer: {
        Text("This permanently deletes your account, trips and saved places. It cannot be undone.")
      }
    }
    .settingsStyle("Your data")
    .errorAlert($error)
  }

  private func export() async {
    isExporting = true
    defer { isExporting = false }
    do {
      let response = try await rpc("Could not export your data.") {
        await SettingsClients.user.exportUserData(request: .init(), headers: [:])
      }
      let name = response.filename.isEmpty ? "loci-data-export.json" : response.filename
      let url = FileManager.default.temporaryDirectory.appending(path: name)
      try response.data.write(to: url, options: .atomic)
      exportedFile = url
    } catch { self.error = error.userMessage }
  }

  private func delete() async {
    isDeleting = true
    defer { isDeleting = false }
    var request = Loci_User_DeleteAccountRequest()
    request.confirmation = deleteConfirmation
    do {
      _ = try await rpc("Could not delete your account.", request) { await SettingsClients.user.deleteAccount(request: $0, headers: [:]) }
      await AuthSessionManager.shared.invalidateSession()
    } catch { self.error = error.userMessage }
  }
}
