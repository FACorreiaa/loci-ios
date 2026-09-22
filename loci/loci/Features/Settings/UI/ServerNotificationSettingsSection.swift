import LociConnectProto
import SwiftUI

/// The account's notification preferences (web: settings tab "notifications").
/// UserService.GetNotificationSettings / UpdateNotificationSettings{recommendations, tripReminders}.
/// These are stored server-side; nothing on the server sends them yet.
struct ServerNotificationSettingsSection: View {
  @State private var settings: Loci_User_NotificationSettings?
  @State private var error: String?

  var body: some View {
    Section {
      if let settings {
        Toggle("Recommendations", isOn: binding(settings.recommendations) { $0.recommendations = $1 })
        Toggle("Trip reminders", isOn: binding(settings.tripReminders) { $0.tripReminders = $1 })
      } else {
        ProgressView()
      }
    } header: {
      Text("Your account")
    } footer: {
      Text("Saved to your account, so they apply on the web too. Search-finished alerts are always on while this iPhone allows notifications.")
    }
    .listRowBackground(Color.lociCard)
    .errorAlert($error)
    .task {
      do {
        settings = try await rpc("Could not load notification settings.") {
          await SettingsClients.user.getNotificationSettings(request: .init(), headers: [:])
        }
      } catch { self.error = error.userMessage }
    }
  }

  private func binding(_ value: Bool, _ apply: @escaping (inout Loci_User_UpdateNotificationSettingsRequest, Bool) -> Void) -> Binding<Bool> {
    Binding(
      get: { value },
      set: { newValue in
        guard let settings else { return }
        var request = Loci_User_UpdateNotificationSettingsRequest()
        request.recommendations = settings.recommendations
        request.tripReminders = settings.tripReminders
        apply(&request, newValue)
        let sent = request
        Task {
          do {
            self.settings = try await rpc("Could not save.", sent) {
              await SettingsClients.user.updateNotificationSettings(request: $0, headers: [:])
            }
          } catch { self.error = error.userMessage }
        }
      }
    )
  }
}
