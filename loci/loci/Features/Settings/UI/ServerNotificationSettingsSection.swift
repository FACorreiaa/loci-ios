import LociConnectProto
import SwiftUI

/// The account's notification preferences (web: settings tab "notifications").
/// UserService.GetNotificationSettings / UpdateNotificationSettings{recommendations, tripReminders, searchFinished, friendActivity}.
/// Search finished and Friends are the ones the server acts on: they gate the push (web and APNs) for a
/// run that ends and for friend requests and acceptances.
struct ServerNotificationSettingsSection: View {
  @State private var settings: Loci_User_NotificationSettings?
  @State private var error: String?

  var body: some View {
    Section {
      if let settings {
        Toggle("Recommendations", isOn: binding(settings.recommendations) { $0.recommendations = $1 })
        Toggle("Trip reminders", isOn: binding(settings.tripReminders) { $0.tripReminders = $1 })
        Toggle("Search finished", isOn: binding(settings.searchFinished) { $0.searchFinished = $1 })
        Toggle("Friends", isOn: binding(settings.friendActivity) { $0.friendActivity = $1 })
        Toggle("Badges and leaderboard", isOn: binding(settings.progressUpdates) { $0.progressUpdates = $1 })
        Toggle("Streak reminder", isOn: binding(settings.streakReminders) { $0.streakReminders = $1 })
        Toggle("Show me on friends' leaderboards", isOn: binding(settings.leaderboardVisible) { $0.leaderboardVisible = $1 })
      } else {
        ProgressView()
      }
    } header: {
      Text("Your account")
    } footer: {
      Text(
        "Saved to your account, so they apply on the web too. Search finished is the push you get when a search you left running ends; "
          + "Friends, when someone sends or accepts a friend request. The streak reminder comes at 7pm on a day you haven't opened Loci yet."
      )
    }
    .listRowBackground(Color.lociCard)
    .errorAlert($error)
    .task {
      do {
        let loaded = try await rpc("Could not load notification settings.") {
          await SettingsClients.user.getNotificationSettings(request: .init(), headers: [:])
        }
        settings = loaded
        StreakReminder.setEnabled(loaded.streakReminders)
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
        request.friendActivity = settings.friendActivity
        request.leaderboardVisible = settings.leaderboardVisible
        request.streakReminders = settings.streakReminders
        request.progressUpdates = settings.progressUpdates
        apply(&request, newValue)
        let sent = request
        Task {
          do {
            let saved = try await rpc("Could not save.", sent) {
              await SettingsClients.user.updateNotificationSettings(request: $0, headers: [:])
            }
            self.settings = saved
            StreakReminder.setEnabled(saved.streakReminders)
          } catch { self.error = error.userMessage }
        }
      }
    )
  }
}
