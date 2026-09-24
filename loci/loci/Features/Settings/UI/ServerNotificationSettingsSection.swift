import LociConnectProto
import SwiftUI

/// The account's notification preferences (web: settings tab "notifications").
/// UserService.GetNotificationSettings / UpdateNotificationSettings{recommendations, tripReminders, searchFinished}.
/// Search finished is the one the server acts on: it gates the push (web and APNs) for a run that ends.
struct ServerNotificationSettingsSection: View {
  @State private var settings: Loci_User_NotificationSettings?
  @State private var error: String?

  var body: some View {
    Section {
      if let settings {
        Toggle("Recommendations", isOn: binding(settings.recommendations) { $0.recommendations = $1 })
        Toggle("Trip reminders", isOn: binding(settings.tripReminders) { $0.tripReminders = $1 })
        Toggle("Search finished", isOn: binding(settings.searchFinished) { $0.searchFinished = $1 })
      } else {
        ProgressView()
      }
    } header: {
      Text("Your account")
    } footer: {
      Text("Saved to your account, so they apply on the web too. Search finished is the push you get when a search you left running ends.")
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
        request.searchFinished = settings.searchFinished
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
