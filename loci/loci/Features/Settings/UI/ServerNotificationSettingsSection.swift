import LociConnectProto
import SwiftUI

/// The account's notification preferences (web: settings tab "notifications").
/// UserService.GetNotificationSettings / UpdateNotificationSettings{recommendations, tripReminders, searchFinished, friendActivity}.
/// Search finished and Friends are the ones the server acts on: they gate the push (web and APNs) for a
/// run that ends and for friend requests and acceptances.
struct ServerNotificationSettingsSection: View {
  @State private var settings: Loci_User_NotificationSettings?
  /// Bumped per save, so only the newest reply (or failure) lands when flips overlap.
  @State private var saveGeneration = 0
  @State private var error: String?

  var body: some View {
    Section {
      if settings != nil {
        Toggle("Recommendations", isOn: binding(\.recommendations))
        Toggle("Trip reminders", isOn: binding(\.tripReminders))
        Toggle("Search finished", isOn: binding(\.searchFinished))
        Toggle("Friends", isOn: binding(\.friendActivity))
        Toggle("Badges and leaderboard", isOn: binding(\.progressUpdates))
        Toggle("Streak reminder", isOn: binding(\.streakReminders))
        Toggle("Show me on friends' leaderboards", isOn: binding(\.leaderboardVisible))
      } else {
        ProgressView()
      }
    } header: {
      Text("Your account")
    } footer: {
      Text(
        """
        Saved to your account, so they apply on the web too. Search finished is the push you get when a search you left running ends; \
        Friends, when someone sends or accepts a friend request. The streak reminder comes at 7pm on a day you haven't opened Loci yet.
        """
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

  /// Flips the switch at once and sends every flag from the updated settings, so
  /// a quick second flip builds on the first rather than on stale values.
  private func binding(_ flag: WritableKeyPath<Loci_User_NotificationSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { settings?[keyPath: flag] ?? false },
      set: { newValue in
        guard let previous = settings else { return }
        var updated = previous
        updated[keyPath: flag] = newValue
        settings = updated
        saveGeneration += 1
        let generation = saveGeneration
        Task { await save(updated, generation: generation, rollback: previous) }
      }
    )
  }

  private func save(_ updated: Loci_User_NotificationSettings, generation: Int, rollback previous: Loci_User_NotificationSettings) async {
    var request = Loci_User_UpdateNotificationSettingsRequest()
    request.recommendations = updated.recommendations
    request.tripReminders = updated.tripReminders
    request.searchFinished = updated.searchFinished
    request.friendActivity = updated.friendActivity
    request.leaderboardVisible = updated.leaderboardVisible
    request.streakReminders = updated.streakReminders
    request.progressUpdates = updated.progressUpdates
    do {
      let saved = try await rpc("Could not save.", request) {
        await SettingsClients.user.updateNotificationSettings(request: $0, headers: [:])
      }
      guard generation == saveGeneration else { return }
      settings = saved
      StreakReminder.setEnabled(saved.streakReminders)
    } catch {
      guard generation == saveGeneration else { return }
      settings = previous
      self.error = error.userMessage
    }
  }
}
